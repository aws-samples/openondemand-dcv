# Open OnDemand DCV integration

# Summary

[**Open OnDemand**](https://openondemand.org/) is a project by the [Ohio Supercomputer Center (OSC)](https://www.osc.edu/) funded with a National Science Foundation grant to develop open source software that provides HPC centers with advanced web ~~~~ interface capabilities to ease access to their HPC resources. , including the support of multiple job schedulers like LSF, Grid Engine, OpenPBS, Torque and Slurm.

[**NICE DCV**](https://aws.amazon.com/hpc/dcv/)  is a remote visualization technology that enables secure connection to graphic-intensive 3D applications hosted on remote servers. The product include a suite of tools like DCV Session Manager, Connection Gateway, CLI, and APIs. With NICE DCV, HPC centers can bring high-performance processing capabilities to remote users through secure client sessions.

This document describes the **integration between Open OnDemand and NICE DCV**. This integration allows Open OnDemand users to easily start, manage and connect to NICE DCV Linux interactive sessions, resulting in:

1. **Improved and simplified end user experience**
2. **Reduced time for users onboarding and achieving business productivity**

Open OnDemand does not currently provide an integration with NICE DCV out of the box. Version 3.0, which this document is referred, just integrates with VNC/TurboVNC as a desktop remotization protocol.

**Products documentation:**
Open OnDemand: https://osc.github.io/ood-documentation/latest/index.html
NICE DCV: https://docs.aws.amazon.com/dcv/

## Logic

We start by looking at VNC integration, and follow the same logic for DCV.

**Both VNC and DCV sessions are managed as HPC jobs.** So you submit a desktop job from Open OnDemand to the underlying HPC workload sheduler, then the integration code sets up VNC or DCV into the remote execution node selected by the sheduler.

### **VNC Integration**

**VNC integration** in Open OnDemand is implemented by its eRuby template ***vnc.rb***, located in the gems folder, e.g. */opt/ood/ondemand/root/usr/share/gems/3.0/ondemand/3.0.0-1/gems/ood_core-0.23.4/lib/ood_core/batch_connect/templates/vnc.rb.*
VNC template manages the VNC session lifecycle on the target compute node, specifically:

1. Sets a one-time password for the session
2. Starts VNC server
3. Waits and checks that VNC server is running correctly
4. Launches [websockify](https://github.com/novnc/websockify) websocket server
5. Closes VNC server on session termination

**User connection URL** (portal *Connect* button) is then created and provided by Open OnDemand by acting as reverse proxy using [nmap-ncat](https://nmap.org/ncat/) and  websockify. Configuration of that URL relies on the [portal configuration file](https://osc.github.io/ood-documentation/latest/reference/files/ood-portal-yml.html#ood-portal-generator-configuration) located at `/etc/ood/config/ood_portal.yml`, where target host regular expressions and URL mappings are defined.


### DCV Integration

**DCV template** mainly follows the same approach.
The main differences will be:

* We’ll use **nice-dcv-simple-external-authenticator**
    This will enable us to automatically authenticate users that are already logged into OnDemand.
* We’ll use an **AWS** [**Application Load Balancer**](https://aws.amazon.com/elasticloadbalancing/application-load-balancer/) **(ALB)** instead of the reverse proxy for our connection URL

## Implementation

As job scheduler, in this document, we are referring to [OpenPBS](https://www.openpbs.org/)v. 22.05.11 , other supported job scheduler can be used, with additional changes.

_**Steps for integrating DCV:**_

1. Check the following **Requirements**
2. Copy **DCV template** (*dcv.rb*) to Open OnDemand templates folder
3. Define a **Connection URL** that users will connect to access DCV sessions. Connection URL can be a direct connection to DCV server (e.g. *[https://indernal-dcv-IP:8443](https://indernal-dcv-ip:8443/)*) or an AWS ALB, like described below
4. Customize Open OnDemand **Desktop Service**

### Code

DCV template for Open OnDemand and *bc_desktop* service sample are stored inside AWS Samples git repository: https://github.com/aws-samples/openondemand-dcv

### 1. Requirements

Even if all the packages can be deployed on a single node, a best practice is to decouple the front-end from the DCV nodes as a fleet dedicated to interactive sessions:

1. **Open OnDemand** version 3.0 installed and running on a node as a front-end. 
2. Open OnDemand must be integrated with one or more **HPC workload schedulers**. 
3. **NICE DCV** packages installed and configured on interactive nodes: 
    1. **nice-dcv-server**
        NICE DCV base requirement
    2. **nice-xdcv**
        NICE DCV base requirement
    3. **nice-dcv-simple-external-authenticator**
        This will enable us to automatically authenticate users that are already logged into OnDemand.
    4. **nice-dcv-web-viewer**
        This will enable to access the DCV Session via web browser
    5. **nice-dcv-gl* packages**
        To enable OpenGL application in case of nodes with GPUs.
4. **Shared file system** to host the User’s home directories
5. **OS**: Centos 7, RHEL 7, Amazon Linux 2

### 2. DCV Template

Template ***dcv.rb***, located in the same folder as *vnc.rb.*
To add it to your Open OnDemand installation, just copy: 
https://github.com/aws-samples/openondemand-dcv/blob/main/templates/dcv.rb
To your Open OnDemand installation templates folder, e.g. 
*/opt/ood/ondemand/root/usr/share/gems/3.0/ondemand/3.0.0-1/gems/ood_core- 0.23.4/lib/ood_core/batch_connect/templates/*

DCV template performs the following actions as the user logged into the portal:

1. **Creates a new dcv session** 
    using command
     `dcv create-session <session id>`.  
    Session id is provided by Open OnDemand via `session_id` variable
2. **Waits and checks till the session is ready** 
    using DCV command:
     ```dcv describe-session <session id>```
3. **Generates a session password and enables it in DCV simple external authenticator** 
    e.g. using ```uuidgen``` and saving it in an hidden file inside the session folder. Password is added to DCV Simple external authenticator list to allow the portal user to connect to his DCV sessions without providing credentials
4. **Intercepts SIGTERM signals** that might be sent by the scheduler to the DCV job, and accordingly closes the session
5. **Closes DCV session** when the related job completes

### 3. Connection URL

For what concerns the ***Connect*** button URL that OnDemand will provide to the end user to connect to his sessions, we can of course re-use the same logic as VNC, so setting up OnDemand to act as a reverse proxy. 

If the environment is on AWS cloud, a more clean and solid alternative is to use an [**Application Load Balancer**](https://aws.amazon.com/elasticloadbalancing/application-load-balancer/) **(ALB).** This approach brings the following advantages:

* **Application Load Balancer derived capabilities:**
    * **High availability** (scales with the traffic) for both Open OnDemand and DCV sessions
        We can include multiple Open OnDemand or DCV nodes and let ALB balance the load on them
    * **Supports the implementation of a fault tolerance policy**, e.g. on a specific DCV node failure redirecting to an healthy one (out of the scope of this document)
    * **Offloads HTTPS** from Open OnDemand (when configured as a frontend for Open OnDemand nodes too)
* **Open OnDemand node/process is not a unique point of failure for DCV sessions**, that could independently continue even if the portal node fails

>***Note:*** if you’re using an ALB in front of Open OnDemand you can use it for DCV sessions as well.


A sample configuration for an ALB managing DCV sessions can be:

1. **Create an HTTPS listener**
    and attach it to the DCV ALB
2. **For each DCV node:**
    1. **Define a unique DCV web URL**
        in each DCV configuration, */etc/dcv/dcv.conf*, define a unique [[connectivity] web-url-path](https://docs.aws.amazon.com/dcv/latest/adminguide/config-param-ref.html#connectivity), e.g. using the host name or the IP: 
        `[connectivity]
        web-url-path=/ip-10-0-0-1`
    2. **Create an EC2 target group**
        Named e.g. `dcv-ip-10-0-0-1`
        Set its *health check* to the instance (or instance IP), DCV port, e.g. 8443, and the related web URL path as *Path*
    3. **Set an HTTPS listener rule** 
        that forwards DCV web URL to its related target group, e.g.:
3. **(Optional) Set the default target group rule to forward requests to Open OnDemand portal**

### 4. Desktop Service

You can create a copy or modify standard **bc_desktop** service, located into */var/www/ood/apps/sys/bc_desktop,* to:

1. **Use DCV template**
2. **Submit a DCV job** with specific settings, e.g. submit in a dedicated `dcv` queue
3. If using ALB, when password file is present in session folder, then generate a custom **Connect** button pointing to the Application Load Balancer DNS address, followed by session password and session id, i.e.:
    `https://ALB_URL/?authToken=<session-password>#<session-id>
    `**
    This is implemented using *info.html.erb*** file, located into the ***bc_desktop*** service folder. Connection URL includes DCV simple authenticator session password: this will automatically authenticate the user into his Linux interactive session without asking for further credentials.
    
    We are also providing a similar link to connect using **NICE DCV client**

Desktop service form example (*/var/www/ood/apps/sys/bc_desktop/form.yml*):

```
---
attributes:
  desktop: "dcv"
  instance_type:
    widget: select
    help: "Instance type"
    options:
      - [ "g4dn.4xlarge", "ip-10-0-0-1" ]
      - [ "g5.4xlarge", "ip-10-0-0-2" ]

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


Submission setting example (*/var/www/ood/apps/sys/bc_desktop/submit.yml.erb*):

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

You can find the full bc_desktop sample in https://github.com/aws-samples/openondemand-dcv/tree/main/bc_desktop

## Screenshots

[Image: image.png]Example of submission form

[Image: image.png]Session is running with Connect button

[Image: image.png]A running session with `dcvgltest` application on Xfce desktop.

## Conclusion

In this document we are enabling easy and handy management of NICE DCV sessions with Open OnDemand HPC portal. This may greatly increase portal user experience with interactive desktop sessions, and also provide reduced time for end users business productivity.

Since NICE DCV is completely free when used in AWS, we also presented a scalable and more solid solution coupling our integration with an AWS EC2 Application Load Balancer.

## Call to Action

Further addition to this integration can leverage [**NICE DCV Session Manager**](https://docs.aws.amazon.com/dcv/latest/sm-admin/what-is-sm.html) to build front-end applications that programmatically create and manage the lifecycle of NICE DCV sessions across a fleet of NICE DCV servers, both on Linux and Windows. 


## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

