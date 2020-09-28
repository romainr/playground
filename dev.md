## Develop, Release, and Use SQLFlow-in-a-VM

### For Developers

1. Install [VirtualBox 6.1.6](https://www.virtualbox.org/) and [Vagrant 2.2.7](https://www.vagrantup.com/) on a computer with a relatively large memory size.  As a recommendation, a host with 16G memory and 8 cores is preferred.
1. Clone and update `SQLFlow playground` project.
    ```bash
    git clone https://github.com/sql-machine-learning/playground.git
    cd playground
    git submodule update --init
    ```
1. Run the `play.sh` under playgound's root directory.  This script will guide you to install SQLFlow on a virtualbox VM.  If you have a slow Internet connection to Vagrant Cloud, you might want to download the Ubuntu VirtualBox image manually from some mirror sites into `~/.cache/sqlflow/` before running the above script.  We use `wget -c` here for continuing get the file from last breakpoint, so if this command fail, just re-run it.
    ```bash
    # download Vagrant image manually, optional
    mkdir -p $HOME/.cache/sqlflow
    wget -c -O $HOME/.cache/sqlflow/ubuntu-bionic64.box \
      "https://mirrors.ustc.edu.cn/ubuntu-cloud-images/bionic/current/bionic-server-cloudimg-amd64-vagrant.box"

    ./play.sh
    ```
    The `play.sh` add some extensions for Vagrant, like `vagrant-disksize` which enlarges the disk size of the VM.  The script will then call `vagrant up` command to bootup the VM.  After the VM is up, the `provision.sh` will be automatically executed which will install the dependencies for SQLFlow.  Provision is a one-shot work, after it is done, we will have an environment with SQLFlow, docker and minikube installed.

1. Log on the VM and start SQLFlow playground.  Run the `start.bash` script, it will pull some docker images and start the playground minikube cluster.  As the images pulling may be slow, the script might fail sometimes.  Feel free to re-run the script until gou get some output like `Access Jupyter Notebook at ...`.
    ```bash
    vagrant ssh
    sudo su
    cd desktop
    ./start.bash
    ```
1. After the minikube is started up. You can access the `Jupyter Notebook` from your desktop. Or you can use SQLFlow command-line tool [sqlflow](https://github.com/sql-machine-learning/sqlflow/blob/develop/doc/run/cli.md) to access the `SQLFlow server`.  Just follow the output of the `start.bash`, it will give you some hint.
1. After playing a while, you may want to stop SQLFlow playground, just log on the VM again and stop the minikube cluster.
    ```bash
    vagrant ssh # optional if you already logged on
    minikube stop
    ```
1. Finally if you want to stop the VM, you can run the `vagrant halt` command.  To complete destroy the VM, run the `vagrant destroy` command.

### For Releaser

The releaser, which, in most cases, is a developer, can export a running VirtualBox VM into a VM image file with extension `.ova`.  An `ova` file is a tarball of a directory, whose content follows the OVF specification.  For the concepts, please refer to this [explanation](https://damiankarlson.com/2010/11/01/ovas-and-ovfs-what-are-they-and-whats-the-difference/).

According to this [tutorial](https://www.techrepublic.com/article/how-to-import-and-export-virtualbox-appliances-from-the-command-line/), releasers can call the VBoxManage command to export a VM. We have written a scrip to do this.  Simply run below script to export our playground.  This script will create a file named `SQLFlowPlayground.ova`, we can import the file through virtual box GUI.

```bash
./release.sh
```

### For End-users

To run SQLFlow on a desktop computer running Windows, Linux, or macOS, follow below steps:
1. install [VirtualBox](https://www.virtualbox.org/) (v6.1.6 is recommended)

1. download the released VirtualBox `.ova` file, you have two choices:
    - the minimized image (about 600M): shipped with all bootstrap files but no dependency docker images. When you start the playground, you will wait for a while to download the latest docker images, minikube framework and other packages.
    ```bash
    wget -c http://cdn.sqlflow.tech/latest/SQLFlowPlaygroundBare.ova
    ```
    - the full installed image (about 2G): with all dependencies, no extra downloading is needed when starting. Note that in this case, the images will not be updated automatically, you will do it manually when needed.
    ```bash
    wget -c http://cdn.sqlflow.tech/latest/SQLFlowPlaygroundFull.ova
    ```
1. optional, download the [sqlflow](https://github.com/sql-machine-learning/sqlflow/blob/develop/doc/run/cli.md) command-line tool released by SQLFlow CI.

After VirtualBox is installed, you can import the `.ova` file and start a VM.  If you have a relative lower configuration, you can adjust the CPU core and RAM amount in VirtualBox's setting panel, say, to 2 cores and 4G RAM.  After that, you can log in the system through the VirtualBox GUI or through a ssh connection like below.  The default password of `root` is `sqlflow`.
```bash
ssh -p2222 root@127.0.0.1
root@127.0.0.1's password: sqlflow
```
Once logged in the VM, you will immediately see a script named `start.bash`, just run the script to start SQLFlow playground.  It will output some hint messages for you, follow those hints, after a while, you will see something like `Access Jupyter NoteBook at: http://127.0.0.1:8888/...`, it means we are all set.  Copy the link to your web browser  and you will see SQLFlow's Jupyter Notebook user interface, Enjoy it!
```bash
./start.bash
```

Or, if you has an AWS or Google Cloud account, you can upload the `.ova` file to start the VM on the cloud.  AWS users can follow [these steps](https://aws.amazon.com/ec2/vm-import/).

Anyway, given a running VM, the end-user can run the following command to connect to it:

```bash
sqlflow --sqlflow-server=my-vm.aws.com:50051
```

### For End-users with Kubernetes (without a VM)

Now, SQLFlow playground supports directly installing on Kubernetes. Users can refer to [this doc](https://github.com/sql-machine-learning/sqlflow/blob/develop/doc/run/kubernetes.md) to apply a fast deployment.
