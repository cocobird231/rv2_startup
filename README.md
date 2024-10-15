# RV2 Package Launcher Management

## Quick Start

### Setup the environment using `curl`
```bash
curl -fsSL ftp://61.220.23.239/rv2-example/deploy.sh | bash
```
The package will be installed in `${HOME}/rv2_startup`.


### Setup the environment using `git`
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
    wget -q -O ${HOME}/rv2_startup/config.yaml ftp://61.220.23.239/rv2-example/config.yaml
    ```

WARNING: The rv2_startup directory should be placed in the home directory.


## Usage

### `config.yaml`
The `config.yaml` file is used to define the package launcher settings. The file should be placed in the `${HOME}/rv2_startup` directory.
```yaml
ROS2_WS_PATH: "~/ros2_ws"
FTP_SERVER_PATH: ""
FTP_SERVER_REPO_VERSION: ""
```
- `ROS2_WS_PATH` (string): The path to the ROS 2 workspace. (Required)
- `FTP_SERVER_PATH` (string): The path to the FTP server. (Optional)
- `FTP_SERVER_REPO_VERSION` (string): The version of the repository on the FTP server. (Optional)

WARNING: If the `FTP_XXX` not set properly, the `update-repos` and `update-repo-list` commands will not work, but the rest of the commands will work normally.
