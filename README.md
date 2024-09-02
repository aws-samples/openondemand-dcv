# Open OnDemand DCV integration

**Professional Services**
Copyright 2024, Amazon Web Services, Inc. or its affiliates. All Rights Reserved. This AWS Content is provided subject to the terms of the AWS Customer Agreement available at http://aws.amazon.com/agreement or other written agreement between Customer and Amazon Web Services, Inc.; provided that AWS grants Customer a worldwide, royalty-free, non-exclusive, nontransferable license to use, reproduce, display, perform, and prepare derivative works of this AWS Content. Except as provided herein, Customer obtains no other rights from AWS, its affiliates, or their licensors to this AWS Content, including without limitation any related intellectual property rights. AWS will be the exclusive owner of any modifications to or derivative works of this AWS Content. Customer acknowledges that this AWS Content is provided “as is” without representations or warranties of any kind. Customer is solely responsible for testing, deploying, maintaining and supporting this AWS Content and for determining the suitability of this AWS Content for its business purposes.

**Roberto Meda, Alberto Falzone
**
**Last update: 2024-05**

# Summary

[**Open OnDemand**](https://openondemand.org/) is a project by the [Ohio Supercomputer Center (OSC)](https://www.osc.edu/) funded with a National Science Foundation grant to develop open source software that provides HPC centers with advanced web ~~~~ interface capabilities to ease access to their HPC resources, including the support of multiple job schedulers like LSF, Grid Engine, PBS, Torque and Slurm.

[**NICE DCV**](https://aws.amazon.com/hpc/dcv/)  is a remote visualization technology that enables secure connection to graphic-intensive 3D applications hosted on remote servers. The product include a suite of tools like DCV Session Manager, Connection Gateway, CLI, and APIs. With NICE DCV, HPC centers can bring high-performance processing capabilities to remote users through secure client sessions.

This document describes the **integration between Open OnDemand and NICE DCV**. This integration allows Open OnDemand users to easily start, manage and connect to NICE DCV Linux interactive sessions, resulting in:

1. **Improved and simplified end user experience**
2. **Reduced time for users onboarding and achieving business productivity**

Open OnDemand does not currently provide an integration with NICE DCV out of the box. Version 3.x, which this document refers to, only integrates with VNC/TurboVNC as a desktop remotization protocol.

Open OnDemand has been successfully installed on **[AWS ParallelCluster](https://aws.amazon.com/blogs/hpc/category/compute/aws-parallel-cluster/)**, too. More details are available in this blog post: https://aws.amazon.com/blogs/hpc/deploying-open-ondemand-on-aws-and-integrating-with-parallel-cluster/

**Products documentation:**
Open OnDemand: https://osc.github.io/ood-documentation/latest/index.html
NICE DCV: https://docs.aws.amazon.com/dcv/

# Logic

We started by looking at VNC integration, and followed a similar logic for implementing the DCV one.

**Both VNC and DCV sessions are managed as HPC jobs.** So when we submit a desktop job from Open OnDemand to the underlying HPC workload scheduler, the integration code sets up VNC or DCV into the remote execution node selected by the scheduler.

## **VNC Integration**

**VNC integration** in Open OnDemand is implemented by its eRuby template ***vnc.rb***, located in the gems folder, e.g. */opt/ood/ondemand/root/usr/share/gems/3.0/ondemand/3.0.0-1/gems/ood_core-0.23.4/lib/ood_core/batch_connect/templates/vnc.rb*
or, in case of 3.1,
*/opt/ood/ondemand/root/usr/share/gems/3.1/ondemand/3.1.4-1/gems/ood_core-0.25.0/lib/ood_core/batch_connect/templates/vnc.rb .*
VNC template manages the VNC session lifecycle on the target compute node, specifically:

1. Sets a one-time password for the session
2. Starts VNC server
3. Waits and checks that VNC server is running correctly
4. Launches [websockify](https://github.com/novnc/websockify) websocket server
5. Closes VNC server on job termination

**User connection URL**, the *Connect* button displayed by Open OnDemand in *My Interactive Sessions* page once the remote session is ready, connects the user through a [reverse proxy](https://en.wikipedia.org/wiki/Reverse_proxy) using [nmap-ncat](https://nmap.org/ncat/) and  websockify. Configuration of that URL relies on the [portal configuration file](https://osc.github.io/ood-documentation/latest/reference/files/ood-portal-yml.html#ood-portal-generator-configuration) located at `/etc/ood/config/ood_portal.yml`, where target host regular expressions and URL mappings must be carefully defined to avoid security concerns.

## DCV Integration

**DCV template** mainly follows the same approach.
The main differences will be:

* We’ll use **nice-dcv-simple-external-authenticator**
    This will enable Single Sign-On (SSO) between Open OnDemand and remote DCV sessions. In other words, portal users will be automatically logged into their remote DCV session without re-entering the credentials they used to log into Open OnDemand
* We’ll use an **AWS** [**Application Load Balancer**](https://aws.amazon.com/elasticloadbalancing/application-load-balancer/) **(ALB)** instead of the reverse proxy for our connection URL. This approach provides more security and scalability

***Please note:** *the underlying HPC scheduler is not relevant for the integration, so we can use any one of the schedulers supported by Open OnDemand.

# Setup

**We have 4 integration steps:**

1. Check the **Requirements**
2. Copy **DCV template** (*dcv.rb*) to Open OnDemand *templates* folder
3. Define a **Connection URL** that users will use to access DCV sessions. Connection URL can refer to an Application Load Balancer DNS, like described in the following sections, or the same portal URL if Open OnDemand acts as a reverse proxy
4. Customize/clone Open OnDemand default **Desktop Service**

## 1. Requirements

We are assuming Open OnDemand and DCV are installed on separated nodes. This is also a best practice, since DCV nodes might be elastic while Open OnDemand portal usually is up and running all the time, waiting for users’ requests.

### **Open OnDemand node requirements**

1. **Open OnDemand** version 3.0 or 3.1 installed and running
2. Open OnDemand must be integrated with one or more supported **HPC workload schedulers**.
3. **A Shared file system** to host the User’s home directories, where by default Open OnDemand saves session data. This is for simplicity, it can theorically be optional

### **NICE DCV node requirements**

1. **NICE DCV** packages installed and configured:
    1. **nice-dcv-server**
        NICE DCV base requirement
    2. **nice-xdcv**
        NICE DCV base requirement
    3. **nice-dcv-simple-external-authenticator**
        This will enable us to automatically authenticate users that are already logged into OnDemand.
    4. **nice-dcv-web-viewer (optional)**
        This will enable to access the DCV Session via web browser
    5. **nice-dcv-gl* packages (for GPU nodes only)**
        To enable OpenGL application in case of nodes with GPUs
2. **NICE DCV server and NICE DCV simple external authenticator** up and running
3. Access to the same **Shared file system** mentioned above for Open OnDemand

## 2. DCV Template

### Code

DCV template for Open OnDemand and *bc_desktop* service sample are stored inside AWS Samples git repository: https://github.com/aws-samples/openondemand-dcv

We have to copy DCV template ***dcv.rb***, into the same folder as VNC one (*vnc.rb).*
To add it to your Open OnDemand installation, just copy: 
https://github.com/aws-samples/openondemand-dcv/blob/main/templates/dcv.rb
To your Open OnDemand installation templates folder, e.g. 
*/opt/ood/ondemand/root/usr/share/gems/3.0/ondemand/3.0.0-1/gems/ood_core- 0.23.4/lib/ood_core/batch_connect/templates/*

DCV template performs the following actions as the user logged into the portal:

1. **Creates a new dcv session** 
    using command
     `dcv create-session <session id>`.  
    Session id is provided by Open OnDemand thorough its `session_id` variable
2. **Waits and checks till the session is ready** 
    using DCV command:
    `dcv describe-session <session id>`
    Session is considered ready when `describe-session` command provides a valid DISPLAY id
3. **Generates a session password and enables it in DCV simple external authenticator** 
    Creates a temporary password and saves it in an hidden file inside the session folder. Password is added to DCV Simple external authenticator list to allow the portal user to connect to his DCV sessions without providing credentials.
    In our DCV template, we are creating a random password using standard Linux command `uuidgen` , but other options are available as well.
4. **Intercepts SIGTERM signals** that might be sent by the scheduler to the DCV job, and consequently closes the session
5. **Closes DCV session** when the related job completes, or when the preset DCV session timeout is reached

## 3. Connection URL

When a Desktop Service job is ready, Open OnDemand will display a ***Connect*** button in My Interactive Sessions page.
This Connect button provides the URL that the browser, or NICE DCV client can use to connect to the DCV session running on the target execution/DCV node.

For managing and maintaining that Connection URL, we have mainly 2 options:

### Option a: Open OnDemand as reverse proxy

In this scenario, connections to DCV servers are managed by **Open OnDemand, which acts as a** [reverse proxy.](https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/setup/enable-reverse-proxy.html)
Open OnDemand uses its built-in reverse proxy feature to connect the user to the remote DCV server host.
Open OnDemand internally triggers its custom ```mod_ood_proxy``` module based on Apache ```mod_proxy``` and a Lua script.

**Connection URL** is in this format:
```https://<Open OnDemand portal URL>/rnode/<DCV server hostname>/<port>/?authToken=<auth token>#<DCV session id>```

**Advantages of this approach:
**

* leverages a built in function of Open OnDemand
* does not require an external entity to monitor and update the URLs/target groups pointing to NICE DCV sessions 

**Disadvantages:**

* Security  concerns (described below)
* Connection  to DCV servers is coupled to Open OnDemand portal being up and running. If OOD is down, user might not be able to connect, or, if permitted, he should rewrite the connection URL to directly contact the target DCV server IP address, and accept its probably invalid HTTPS certificate
* If not  using an ALB in front of OOD, scaling can be impaired, since each OOD node  must have its own persistent IP and related certificate.

**Security concerns**

* Open  Ondemand connection URLs regular expression, controlling DCV server  hostname, must be carefully set to avoid phishing, like described here: [3.  Enable Reverse Proxy — Open OnDemand 3.1.0 documentation (osc.github.io)](https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/setup/enable-reverse-proxy.html#steps-to-enable-in-apache)
    A regular expression sample can be:
    ```host_regex:  'ip-[\d-]+\.ec2\.internal'```
* Since  OOD reverse proxy will be SSL enabled, it will try to check the target DCV node HTTPS certificate. Unless this certificate is valid and its creation managed, it will be self-signed and consequently refused. A quick option would be for the OOD reverse proxy configuration to skip target certificate check through [```SSLProxyCheckPeer*```](https://httpd.apache.org/docs/current/mod/mod_ssl.html#sslproxycheckpeername) directives. But this is not secure. E.g.
    ```SSLProxyCheckPeerN`ame off````
    ```SSLProxyCheckPeerCN off```

### Option b: Using an Application Load Balancer

If the environment is on AWS cloud, a more clean and solid alternative is to use an [**Application Load Balancer**](https://aws.amazon.com/elasticloadbalancing/application-load-balancer/) **(ALB).** 
In this scenario, an ALB manages connections to each DCV server, by defining:

* an **HTTPS listener**, listening on port 443, 
* one **target group** for each DCV node with health checks referring to DCV server port, 8443
* (optional) **A default target group can connect the user to Open OnDemand portal**

Target groups for **elastic DCV nodes must be created and updated by an external entity** such as a Lambda function. That entity that should update the target groups according to the available DCV nodes, scaled up and down by the underlying HPC scheduler.

**Connection URL to DCV session result in this format:
**```https://<ALB URL>/<DCV server hostname>/?authToken=<authentication token>#<DCV session id>```

**Advantages of this solution:** 

* decouple  connection link from Open OnDemand, user can connect to his DCV sessions even if the portal is unavailable
* security  and certificates are managed by ALB settings, offloading secure connection
* includes  a health check for each DCV server
* ALB addresses fault tolerance and high availability. Can potentially scale with multiple OOD servers

**Disadvantages:**

* target  groups for elastic nodes must be defined and updated by an external entity

A sample configuration for an ALB managing DCV sessions can be:

1. **Create an HTTPS listener**
    and attach it to the DCV ALB
2. **For each DCV node:**
    1. **Define a unique DCV web URL**
        in each DCV configuration, */etc/dcv/dcv.conf*, define a unique [[connectivity] web-url-path](https://docs.aws.amazon.com/dcv/latest/adminguide/config-param-ref.html#connectivity), e.g. using the host name or the IP: 
        `[connectivity]
        web-url-path=/ip-172-31-28-198`
    2. **Create an EC2 target group**
        Named e.g. `ip-172-31-22-226-tg`
        Set its *health check* to the instance (or instance IP), DCV port, e.g. 8443, and the related web URL path as *Path*
        Set health check http return codes to: `200,301` (moved permanently redirect):


    1. **Set an HTTPS listener rule 
        **that forwards each DCV web URL path to its related target group
    2. (Optional) Set the default target group rule to forward requests to Open OnDemand portal




## 4. Desktop Service

By default, Open OnDemand installs a desktop service. We can start from that one and customize it for our environment.
Default service is named **bc_desktop**, and it’s located into */var/www/ood/apps/sys/bc_desktop. 
*
We can modify it to:

1. **Set our desired form options**
    By modifying ***bc_desktop/form.yml** file.* 
    E.g. adding a dropdown allowing the users to select in which pre-existing DCV node to start the session
2. **Use DCV template**
    This is set inside job submission script file: ***bc_desktop/submit.yml.erb**:*
    `batch_connect:
      template: "dcv"`
3. **Submit a DCV job** with the target scheduler submission options
     e.g. submit to a dedicated `dcv` queue
    This is set inside job submission script file: ***bc_desktop/submit.yml.erb**:*
    `queue_name: "dcv"`
4. **When the session is ready, display Connect and Connect via DCV Client** buttons pointing to the Application Load Balancer DNS address, followed by a session id and a temporary session password i.e.:
    `https://ALB_URL/?authToken=<session-password>#<session-id>
    `Session ready check and Connect buttons are managed by ***bc_desktop/info.html.erb*** file

You can refer to bc_desktop full service code provided in our GitHub repository: 
https://github.com/aws-samples/openondemand-dcv/tree/main/bc_desktop

## Desktop service examples

**Desktop service form example** 
file: */var/www/ood/apps/sys/bc_desktop/form.yml*
Example allows the user to select a preset DCV server instance type and the DCV session timeout.

```
---
attributes:
  desktop: "dcv"
  instance_type:
    widget: select
    help: "Instance type"
    options:
      - [ "Tesla T4, 16Gb RAM", "ip-172-31-28-198" ]
      - [ "A10G Tensor Core, 32 Gb RAM", "ip-172-31-22-226" ]

  session_timeout:
    widget: select
    options:
      - [ "2 hours", "2h" ]
      - [ "4 hours", "4h" ]
      - [ "8 hours", "8h" ]
      - [ "1 day", "1d" ]
      - [ "4 days", "4d" ]
    label: "Session timeout"

form:
  - desktop
  - instance_type
  - session_timeout
```

Screenshot of the resulting service form:
**Desktop SLURM job submission example** 
file: */var/www/ood/apps/sys/bc_desktop/submit.yml.erb*
Example sets the job queue and the job name to `dcv`.

```
---
cluster: "slurm_cluster"
batch_connect:
  template: "dcv"
script:
  job_name: "dcv"
  queue_name: "dcv"
```

**Desktop PBS job submission example** 
file: */var/www/ood/apps/sys/bc_desktop/submit.yml.erb*
Example sets the job queue to `dcv`, job name to `dcv` and adds custom submission options. In this case it is forcing the job to run on the preselected DCV node and passing on the DCV session timeout environment variable to the job script.

```
---
cluster: "pbs_cluster"
batch_connect:
  template: "dcv"
script:
  job_name: "dcv"
  queue_name: "dcv"
  native:
    - "-l"
    - "nodes=<%= server %>"
    - "-v"
    - "DCV_SESSION_TIMEOUT=<%= session_timeout %>"
```

# Connection

Once the user clicks on Submit, he will be redirected to **My Interactive Sessions** page.
When the DCV session is active, the Connect buttons will appear, like in the following screenshot:
**Connect via NICE DCV client** button will download a small ***.dcv*** file that can be opened with NICE DCV client.
In case user doesn’t want to (or can) download anything, he can press **Copy connection URL** button and paste the DCV session connection URL into an open NICE DCV client.
Above we see a running session with `dcvgltest` application on a GNOME desktop.

# Conclusion

In this document we are enabling easy and handy management of NICE DCV sessions with Open OnDemand HPC portal. This may greatly increase portal user experience with interactive desktop sessions, and also provide reduced time for end users business productivity.

Since NICE DCV is completely free when used in AWS, we also presented a scalable and more solid solution coupling our integration with an AWS EC2 Application Load Balancer.

# Call to Action

Further addition to this integration can leverage [**NICE DCV Session Manager**](https://docs.aws.amazon.com/dcv/latest/sm-admin/what-is-sm.html) to build front-end applications that programmatically create and manage the lifecycle of NICE DCV sessions across a fleet of NICE DCV servers, both on Linux and Windows. 
