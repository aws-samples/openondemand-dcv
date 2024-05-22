require "ood_core/refinements/hash_extensions"

module OodCore
  module BatchConnect
    class Factory
      using Refinements::HashExtensions

      # Build DCV template from a configuration
      # @param config [#to_h] the configuration for the batch connect template
      def self.build_dcv(config)
        context = config.to_h.compact.symbolize_keys
        Templates::DCV.new(context)
      end
    end

    module Templates
      # A batch connect template that starts up a DCV within a batch job
      class DCV < Template

        def initialize(context = {})
          super
        end

        private
          # Before running the main script, start up DCV
          def before_script
            <<-EOT.gsub(/^ {14}/, "")
              #{super}
              _username=$(whoami)
              # retrieve connection url name
              ip_addresses=$(ip -o address show | awk '$2 == "lo" { next } $2 == "virbr0" { next } $3 == "inet" { print substr($4,1,index($4,"/")-1)}')
              hostname_ip=$(hostname -s | sed 's/^ip-//;s/-/\./g')
              url_path=$(echo "${ip_addresses}" | sed '/'"${hostname_ip}"'/!d' | sed 's/\\./-/g;s/^/ip-/')
              dcv_server=$(echo "${url_path}" | tr -d '\\n')
              printf "${dcv_server}" > .server
              # create session
              dcv create-session --storage-root "${HOME}" #{session_id}
              dcv list-sessions
              _iterator=0
              # check session is ready using dcv describe-session
              while true; do
                  echo "session ready check ${_iterator}..."
                  display=$(2>/dev/null dcv describe-session #{session_id} | awk '/X display: / { print $3 }')
                  [ "$?" -eq 0 -a -n "${display}" ] && break
                  if [ "$_iterator" -gt 10 ]; then
                      echo "describe-session failed" >&2
                      exit 1
                  fi
                  _iterator=$(( _iterator+1 ))
                  sleep $_iterator
              done
              # set external auth if available
              auth_verifier=$(cat /etc/dcv/dcv.conf | \
                  sed '/^[ \t]*auth-token-verifier[ \t]*=[ \t]*/!d;s/^[ \t]*auth-token-verifier[ \t]*=[ \t]*\([^ #][^ #]*\).*$/\1/' | \
                  sed 's/"//g')
              if [ -n "${auth_verifier}" ]; then
                  _session_pwd=$(uuidgen)
                  printf "${_session_pwd}" | base64 > .session.pwd
                  chmod 600 .session.pwd
                  echo "${_session_pwd}" | \
                      dcvsimpleextauth add-user --user "${_username}" --session #{session_id} \
                      --auth-dir /var/run/dcvsimpleextauth/ --append
              fi
              # finally, save a .dcv file to use with NICE DCV Client
              echo "[version]" > #{session_id}.dcv
              echo "format=1.0" >> #{session_id}.dcv
              echo "" >> #{session_id}.dcv
              echo "[connect]" >> #{session_id}.dcv
              echo "host=${ALB_URL}" >> #{session_id}.dcv
              echo "weburlpath=/${dcv_server}" >> #{session_id}.dcv
              echo "port=443" >> #{session_id}.dcv
              echo "sessionid=#{session_id}" >> #{session_id}.dcv
              echo "authtoken=${_session_pwd}" >> #{session_id}.dcv
            EOT
          end

          # Run the script
          def run_script
            %(DISPLAY=${display} #{super})
          end

          # After startup the main script
          def after_script
            <<-EOT.gsub(/^ {14}/, "")
              #{super}
              trap "dcv close session #{session_id}" SIGTERM
              _periodic=30
              _logdir="/var/log/dcv/"
              _custom_logdir=$(cat /etc/dcv/dcv.conf | sed '/^ *directory *= */!d;s/directory *= *//g')
              [ -n "${_custom_logdir}" ] && _logdir=${_custom_logdir}
              _dcvserver_log="${_logdir}/server.log"
              _dcvagent_log="${_logdir}/agent.${_username}.#{session_id}.log"
              _xdcv_log="${_logdir}/Xdcv.${_username}.#{session_id}.log"
              _dcvxsession_log="${_logdir}/dcv-xsession.${_username}.#{session_id}.log"

              # periodically check pid and dump logs
              ( while true; do
                  sleep ${_periodic}
                  cp -a ${_dcvserver_log} dcv-server.log
                  cp -a ${_dcvagent_log} dcv-agent.log
                  cp -a ${_xdcv_log} dcv-session.log
                  cp -a ${_dcvxsession_log} dcv-xdcv.log
                  [[ ${SCRIPT_PID} ]] || break
              done ) &
            EOT
          end

          # Clean up
          def clean_script
            <<-EOT.gsub(/^ {14}/, "")
              #{super}
              touch .session_complete
              dcv close-session #{session_id}
            EOT
          end

          # Get session id from work_dir
          def session_id
            context.fetch(:work_dir).to_s.scan(/^.*\/([^\/]*)$/)[0][0]
          end
      end
    end
  end
end