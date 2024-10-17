# RV2 Package Launcher Management

## File Tree

- **rv2_startup**
    ```plaintext
    rv2_startup
    ├── content
    │   ├── scripts
    │   │   ├── run-internet-check.sh
    │   │   └── run-network-check.sh
    │   └── packages.yaml (generated by `update-repo-list`)
    ├── launch
    │   ├── scripts
    │   │   ├── <package_name>_<id> (generated by `create`)
    │   │   │   ├── params.yaml
    │   │   │   └── system.yaml
    │   │   └── ...
    │   └── services
    │       ├── rv2_startup_<package_name>_<id>.service (generated by `create-service`)
    │       └── ...
    ├── log
    │   └── <YYYY_MM_DD>.log (generated by `setup.sh`)
    ├── setup.sh
    ├── config.yaml (Grab from FTP server)
    └──README.md
    ```

- **RV2 Package Structure**
    ```plaintext
    rv2_ros2_ws (ROS2 workspace)
    ├── src
    │   ├── <rv2_package>
    │   │   ├── include/<package_name>
    │   │   │   └── ...
    │   │   ├── launch
    │   │   │   └── launch.py
    │   │   ├── params
    │   │   │   ├── params.yaml
    │   │   │   └── system.yaml
    │   │   ├── scripts
    │   │   │   ├── custom.sh (optional)
    │   │   │   ├── script_after_build.sh (optional)
    │   │   │   ├── script_before_build.sh (optional)
    │   │   │   └── source_env.sh (optional)
    │   │   ├── src
    │   │   │   └── ...
    │   │   ├── CMakeLists.txt
    │   │   ├── package.xml
    │   │   ├── requirements_apt.txt (optional)
    │   │   ├── requirements_pip.txt (optional)
    │   │   └── ...
    │   └── ...
    └── ...
    ```
    **NOTE**: If the package is an interface package, the `launch` and `params` directories will not be used.

    **NOTE**: If the package is an interface package, the `custom.sh` and `source_env.sh` scripts will not be used.

- **Global Packages**

    Now the package launcher support the global packages that follows the `rv2_package` structure. The global packages usually placed in the `/opt/ros/${ROS_DISTRO}/shared` directory.

    **NOTE**: The global packages will not be built by the `build` command.

    **WARNING**: User should avoid using same package name in the global packages and the ROS2 workspace.

- **Interface Packages**

    The interface packages contains ROS2 interfaces such as `msg`, `srv` etc.. The interface packages can be `create` and `build` but not `create-service` since the interface packages is not a launchable package.

    To `create` an interface package, add the `--pkg-interface` flag to the command. The created directory will be empty.


## Terminology
- **Package Launcher**: A package launcher is a directory that contains the `params.yaml` and `system.yaml` files. The package launcher is used to manage the ROS2 package and the `service`. The package launcher name should be composed of the `package name` and the ID: `<package_name>_<id>`.

- **Service**: A `systemd` service file that manages the package launcher. The service file name should be composed of the package name and the ID: `rv2_startup_<package_name>_<id>.service`.

- **Package Name**: A ROS2 package name defined in the `package.xml`. should be under the repository directory.

- **Repository Name**: A repository directory name. A repository directory contains one or more ROS2 packages.


## Quick Start

### Prerequisites
- OS: Ubuntu 22.04
- ROS2: Humble


### Installation
- Setup the environment using `curl`
    ```bash
    curl -fsSL ftp://61.220.23.239/rv2-example/deploy.sh | bash
    ```
    The package will be installed in `${HOME}/rv2_startup`.

- Setup the environment using `git`
    1. Install required packages
        ```bash
        sudo apt update
        sudo apt install -y python3-yaml
        ```

    2. Clone the repository
        ```bash
        git clone https://github.com/cocobird231/rv2_startup.git ${HOME}/rv2_startup
        ```

    3. Grab `config.yaml`
        ```bash
        wget -O ${HOME}/rv2_startup/config.yaml ftp://61.220.23.239/rv2-example/config.yaml
        ```

    **WARNING**: The `rv2_startup` directory should be placed in the home directory.



## Usage

### First Time Setup
1. Config the `config.yaml` file in `${HOME}/rv2_startup`. Set the `ROS2_WS_PATH` to the ROS2 workspace path. If FTP server is used, set the `FTP_SERVER_PATH` and `FTP_SERVER_REPO_VERSION` properly.
    ```yaml
    # config.yaml
    ROS2_WS_PATH: "~/rv2_ros2_ws"
    FTP_SERVER_PATH: ""
    FTP_SERVER_REPO_VERSION: ""
    ```

2. Update the repository list from the FTP server. (Optional)
    ```bash
    . setup.sh update-repo-list
    ```

3. Update the repositories under the ROS2 workspace source directory. (Optional)
    ```bash
    . setup.sh update-repos
    ```


### Create a Package Launcher
The package launcher name should be composed of the package name and the ID: `<package_name>_<id>`. The `<package_name>` is the ROS2 package name defined in the `package.xml`, and the `<id>` is the unique ID of the package launcher.

1. Create a new package launcher.
    ```bash
    . setup.sh create --pkg-name <package_name> --pkg-id <id>
    ```
    The package launcher directory `<package_name>_<id>` will be created in the `rv2_startup/launch/scripts`, and the files under repository `params` directory will be copied to the package launcher directory.

    **NOTE**: If the package is an interface package, add the `--pkg-interface` flag to the command. The created directory will be empty.

2. Config the `system.yaml` file in the package launcher directory. Set the `network` field properly.
    ```yaml
    # system.yaml
    network:
        interface: "eth0"
        internet_required: false
    ```
    The `interface` should be the network interface that the program will use. If `internet_required` set to `true`, the program will check the internet connection before starting the program.

    **NOTE**: Ignore this step if the package is an interface package.

3. Create a systemd service and runfile. The service will be enabled after service creation.
    ```bash
    . setup.sh create-service --pkg-name <package_name> --pkg-id <id>
    ```
    The service file `rv2_startup_<package_name>_<id>.service` will be created in `rv2_startup/launch/services` directory, and `runfile.sh` will be created in the package launcher directory.

    **NOTE**: Ignore this step if the package is an interface package.

4. Build the ROS2 workspace.
    ```bash
    . setup.sh build
    ```
    The ROS2 workspace will be built accrording to the packages in the `rv2_startup/launch/scripts`. The global packages will not be built.

5. Start the service, or reboot the system to start the service automatically.
    ```bash
    sudo systemctl start rv2_startup_<package_name>_<id>.service
    ```
    **WARNING**: The service will fail to start if the package is not built.

**NOTE**: The order of step 3 and 4 can be swapped. The step 4 could be ignored if all the package launchers are using global packages.


### Remove a Package Launcher
1. Remove the `<package_name>_<id>` package launcher.
    ```bash
    . setup.sh remove --pkg-name <package_name> --pkg-id <id>
    ```
    The package launcher directory `<package_name>_<id>` will be removed from the `rv2_startup/launch/scripts`, and the service will be removed, the service file `rv2_startup_<package_name>_<id>.service` will be removed from the `rv2_startup/launch/services`.

### Re-create a `systemd` Service
If the package launcher directory `<package_name>_<id>` exists, run the following command to re-create the service.
```bash
. setup.sh create-service --pkg-name <package_name> --pkg-id <id>
```
The `remove-service` will be called before creating the service.


### Show Logs

#### Logs of the `setup.sh` Script
- Show more information while running the setup script.
    ```bash
    . setup.sh --debug
    ```
    **NOTE**: The `--debug` option controls the debug message printed in the terminal. The debug message will always be written to the log files.

- The log files located at `${HOME}/rv2_startup/log/<YYYY_MM_DD>.log`.

- If using `--gui-mode`, the log messages will formed with specific prefixes, suffixes, and delimiters. The mode is designed for the GUI application for easier parsing the log messages to the GUI.

#### Logs of the `systemd` Service
- Show the logs of the `rv2_startup_<package_name>_<id>.service`.
    ```bash
    sudo journalctl -u rv2_startup_<package_name>_<id>.service
    ```



## Description

### `config.yaml`
The `config.yaml` file is used to define the package launcher settings. The file should be placed in the `${HOME}/rv2_startup` directory.
```yaml
ENVIRONMENT_SETUP:
    ROS2_WS_PATH: "~/rv2_ros2_ws"
    FTP_SERVER_PATH: ""
    FTP_SERVER_REPO_VERSION: ""

# The following parameters are used to search the ROS2 package under global shared directory.
ROS2_SHARE_PKG_NAME_REGEX:
    RV2_PKG_NAME_REGEX: "^rv2_[a-z0-9_]+"
    # Customized package name regex can be added here.
```
- `ROS2_WS_PATH` (string): The path to the ROS2 workspace. (Required)
- `FTP_SERVER_PATH` (string): The path to the FTP server. (Optional)
- `FTP_SERVER_REPO_VERSION` (string): The version of the repository on the FTP server. (Optional)
- `RV2_PKG_NAME_REGEX` (string): The regular expression to search the ROS2 package under the global shared directory. (Optional)

**WARNING**: If the `FTP_XXX` not set properly, the `restore-repos`, `update-repos` and `update-repo-list` commands will not work, and `list` can only use `scripts` and `services`. The rest of the commands will work normally.


### `packages.yaml`
The `packages.yaml` file is stored under `rv2_startup/content` directory. The file describes the repositories that can be tracked and fetched from online git servers.

The `packages.yaml` file can be generated by the `update-repo-list` command, users can also manually create the file with the following format:
```yaml
packages:
    rv2_package_example:
        description: "RV2 Example Package"
        url: "https://github.com/cocobird231/rv2_package_example.git"

    <package_name>:
        description: "Some description"
        url: "<git repository url>"
```
**NOTE**: The `<package_name>` should be the ROS2 package name defined in the `package.xml`.

**NOTE**: If the `packages.yaml` is customized, do not run the `update-repo-list` command, or the file will be overwritten.


### Commands
- **`--pkg-name <package_name>`**:

    The name of the ROS2 package (Defined in `package.xml`).

- **`--pkg-id <id>`**:

    The ID of the package launcher. The ID must fit the regular expression `[a-zA-Z0-9\.]+`.

- **`--pkg-interface`**:

    Set the flag if `<package_name>` is an interface package. The interface package will be built under ROS2 workspace if it is a local package.

    **WARNING**: The interface package will not create a service since the interface package is not a launchable package.

- **`create {--pkg-name <package_name>} {--pkg-id <id>} [--pkg-interface]`**:

    Create a new package launcher. The package launcher directory `<package_name>_<id>` will be created in the `rv2_startup/launch/scripts`, and the file under `params` directory will be copied to the package launcher directory.

- **`create-service {--pkg-name <package_name>} {--pkg-id <id>}`**:

    Create a systemd service.
    1. First run `custom.sh` if exists in the repository `scripts` directory.
    2. Create `runfile.sh` in the package launcher directory. If `source_env.sh` exists in the repository `scripts` directory, the `source_env.sh` will be appended to the `runfile.sh` before the `ros2 launch` command.
    3. Create a systemd service file `rv2_startup_<package_name>_<id>.service` in the `rv2_startup/launch/services` directory.

    **WARNING**: The `system.yaml` file should be placed in the package launcher directory, and the `network` field should be set properly.

- **`remove-service {--pkg-name <package_name>} {--pkg-id <id>}`**:

    Remove a systemd service. The service and file of `rv2_startup_<package_name>_<id>.service` will be removed, and the `runfile.sh` will be removed from the package launcher directory.

- **`remove {--pkg-name <package_name>} {--pkg-id <id>}`**:

    Remove a package launcher. The `remove-service` command will be executed before removing the package launcher directory.

- **`build [--clean] [--depend]`**:

    Build the ROS2 workspace. The ROS2 workspace will be built according to the packages in the `rv2_startup/launch/scripts`.

    - **`--clean`**: Clean the `build`, `install` and `log` directories before building.
    - **`--depend`**: Force install the dependencies before building.

- **`restore-repos`**:

    Restore the repositories under the ROS2 workspace source directory. The repositories will be restored according to the `packages.yaml` file which is generated under `rv2_startup/content` by the `update-repo-list` command.

    **WARNING**: This command will not modify the repositories which are not listed in the `packages.yaml` file.

    **WARNING**: The changes in the repositories will be lost after running this command.

- **`update-repos [--clean]`**:

    Update the repositories under the ROS2 workspace source directory. The repositories will be updated according to the `packages.yaml` file which is generated under `rv2_startup/content` by the `update-repo-list` command.

    - **`--clean`**: Clean the repositories before updating.

    **WARNING**: This command will not modify the repositories which are not listed in the `packages.yaml` file.

    **WARNING**: Without the `--clean` option, the changes in the repositories will be kept after running this command.

- **`update-repo-list`**:

    Update the repository list from the FTP server. The `packages.yaml` file will be generated under `rv2_startup/content`.

    **WARNING**: The `FTP_SERVER_PATH` and `FTP_SERVER_REPO_VERSION` should be set properly in the `config.yaml` file.

- **`list {all|repos|scripts|services}`**:

    List the package launchers and repositories.

    - **`all`**: List all the package launchers and repositories. The printed information: `<pkg_launcher_name> <pkg_launcher_status> <package_name> <repo_tracked> <repo_fetched>`
        - `<pkg_launcher_name>` (string): The package launcher directory.
        - `<pkg_launcher_status>` (0|1): 0 for no service, 1 for service installed.
        - `<package_name>` (string): The ROS2 package name.
        - `<repo_tracked>` (0|1): 0 for not tracked, 1 for tracked.
        - `<repo_fetched>` (0|1): 0 for not fetched, 1 for fetched.

    - **`repos`**: List the repositories. The printed information: `<package_name> <repo_tracked> <repo_fetched>`
        - `<package_name>` (string): The ROS2 package name.
        - `<repo_tracked>` (0|1): 0 for not tracked, 1 for tracked.
        - `<repo_fetched>` (0|1): 0 for not fetched, 1 for fetched.

    - **`scripts`**: List the package launchers. The printed information: `<pkg_launcher_name> ... <pkg_launcher_name>`

    - **`services`**: List the package launchers that have services. The printed information: `<pkg_launcher_name> ... <pkg_launcher_name>`

- **`--gui-mode`**:

    The flag will formed the output and log messages with specific prefixes, suffixes, and delimiters. The mode is designed for the GUI application for easier parsing the log messages to the GUI.

- **`--debug`**:

    Print more information while running the setup script. The debug message will always be written to the log files.
