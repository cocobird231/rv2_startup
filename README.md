# RV2 Package Launcher Management

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
    ROS2_WS_PATH: "~/ros2_ws"
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
1. Create a new package launcher.
    ```bash
    . setup.sh create --pkg-name <package_name> --pkg-id <id>
    ```
    The package directory `<package_name>_<id>` will be created in the `rv2_startup/launch/scripts`, and the files under repository `params` directory will be copied to the package directory.

2. Config the `system.yaml` file in the package directory. Set the `network` field properly.
    ```yaml
    # system.yaml
    network:
        interface: "eth0"
        internet_required: false
    ```
    The `interface` should be the network interface that the program will use. If `internet_required` set to `true`, the program will check the internet connection before starting the program.

3. Create a systemd service and runfile. The service will be enabled after service creation.
    ```bash
    . setup.sh create-service --pkg-name <package_name> --pkg-id <id>
    ```
    The service file `<package_name>_<id>.service` will be created in `rv2_startup/launch/services` directory, and `runfile.sh` will be created in the package directory.

4. Build the ROS2 workspace.
    ```bash
    . setup.sh build
    ```
    The ROS2 workspace will be built accrording to the packages in the `rv2_startup/launch/scripts`.

5. Start the service, or reboot the system to start the service automatically.
    ```bash
    sudo systemctl start <package_name>_<id>.service
    ```
    **WARNING**: The service will fail to start if the ROS2 workspace is not built.

**NOTE**: The order of step 3 and 4 can be swapped.


### Remove a Package Launcher
1. Remove the `<package_name>_<id>` package launcher.
    ```bash
    . setup.sh remove --pkg-name <package_name> --pkg-id <id>
    ```
    The package directory `<package_name>_<id>` will be removed from the `rv2_startup/launch/scripts`, and the service will be removed, the service file `<package_name>_<id>.service` will be removed from the `rv2_startup/launch/services`.

### Re-create a `systemd` Service
If the package directory `<package_name>_<id>` exists, run the following command to re-create the service.
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

- The log files located at `${HOME}/rv2_startup/log/<YYYY_MM_DD>.log`.

- If using `--gui-mode`, the log messages will formed with specific prefixes, suffixes, and delimiters. The mode is designed for the GUI application for easier parsing the log messages to the GUI.

#### Logs of the `systemd` Service
- Show the logs of the `<package_name>_<id>.service`.
    ```bash
    sudo journalctl -u <package_name>_<id>.service
    ```



## Description

### `config.yaml`
The `config.yaml` file is used to define the package launcher settings. The file should be placed in the `${HOME}/rv2_startup` directory.
```yaml
ROS2_WS_PATH: "~/ros2_ws"
FTP_SERVER_PATH: ""
FTP_SERVER_REPO_VERSION: ""
```
- `ROS2_WS_PATH` (string): The path to the ROS2 workspace. (Required)
- `FTP_SERVER_PATH` (string): The path to the FTP server. (Optional)
- `FTP_SERVER_REPO_VERSION` (string): The version of the repository on the FTP server. (Optional)

**WARNING**: If the `FTP_XXX` not set properly, the `update-repos` and `update-repo-list` commands will not work, but the rest of the commands will work normally.


### Commands
- **`--pkg-name <package_name>`**: 
    The name of the ROS2 package (Defined in `package.xml`).

- **`--pkg-id <id>`**: 
    The ID of the package launcher. The ID must fit the regular expression `[a-zA-Z0-9\.]+`.

- **`create {--pkg-name <package_name>} {--pkg-id <id>}`**: 
    Create a new package launcher. The package directory `<package_name>_<id>` will be created in the `rv2_startup/launch/scripts`, and the file under `params` directory will be copied to the package directory.

- **`create-service {--pkg-name <package_name>} {--pkg-id <id>}`**: 
    Create a systemd service.

    1. First run `custom.sh` if exists in the repository `scripts` directory.
    2. Create `runfile.sh` in the package directory. If `source_env.sh` exists in the repository `scripts` directory, the `source_env.sh` will be appended to the `runfile.sh` before the `ros2 launch` command.
    3. Create a systemd service file `<package_name>_<id>.service` in the `rv2_startup/launch/services` directory.

    **WARNING**: The `system.yaml` file should be placed in the package directory, and the `network` field should be set properly.

- **`remove-service {--pkg-name <package_name>} {--pkg-id <id>}`**: 
    Remove a systemd service. The service and file of `<package_name>_<id>.service` will be removed, and the `runfile.sh` will be removed from the package directory.

- **`remove {--pkg-name <package_name>} {--pkg-id <id>}`**: 
    Remove a package launcher. The `remove-service` command will be executed before removing the package directory.

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
