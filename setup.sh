#!/bin/bash

HOME_PATH=${HOME}
STARTUP_NAME=rv2_startup

STARTUP_PATH=${HOME_PATH}/${STARTUP_NAME}
STARTUP_CONTENT_PATH=${STARTUP_PATH}/content
STARTUP_LOG_PATH=${STARTUP_PATH}/log
STARTUP_PKG_SCRIPTS_PATH=${STARTUP_PATH}/launch/scripts
STARTUP_PKG_SERVICES_PATH=${STARTUP_PATH}/launch/services
STARTUP_TMP_PATH=${STARTUP_PATH}/.tmp

VALID_PACKAGE_ID_REGEX='[a-zA-Z0-9\.]+'


# Automatically set by Init().
ROS2_DEFAULT_SHARE_PATH=""
PYTHON3_PATH=""
LOG_FILE_PATH=""

# Configured in the config.yaml, set by Init().
ROS2_WS_PATH=${HOME_PATH}/ros2_ws
ROS2_WS_SRC_PATH=${ROS2_WS_PATH}/src # Automatically set while ${ROS2_WS_PATH} is set.
FTP_SERVER_PATH=""
FTP_SERVER_REPO_VERSION=""


# Input parameters
PACKAGE_NAME=NONE
PACKAGE_ID=NONE
SETUP_MODE=-1 # 0: create, 1: create-service, 2: remove-service, 3: remove, 4: build, 5: restore-repos, 6: update-repos, 7: update-repo-list, 8: list
LIST_MODE=NONE # all, repos, scripts, services


# Set by input parameters
CLEAN_FLAG=0
DEPEND_FLAG=0
GUI_MODE=0
SHOW_DEBUG_FLAG=0
SILENT_MODE=0



# Repo arr will be set by the CheckRepoList()
REPO_NEED_UPDATE=1 # Start-up and UpdateRepoList will set it to 1.
REPO_PKG_NAME_ARR=()
REPO_PKG_DESC_ARR=()
REPO_PKG_URL_ARR=()

REPO_INTER_NAME_ARR=()
REPO_INTER_DESC_ARR=()
REPO_INTER_URL_ARR=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --pkg-name)
            PACKAGE_NAME=$2
            shift # past argument
            shift # past argument
            ;;
        --pkg-id)
            PACKAGE_ID=$2
            shift # past argument
            shift # past argument
            ;;
        create)
            SETUP_MODE=0
            shift # past argument
            ;;
        create-service)
            SETUP_MODE=1
            shift # past argument
            ;;
        remove-service)
            SETUP_MODE=2
            shift # past argument
            ;;
        remove)
            SETUP_MODE=3
            shift # past argument
            ;;
        build)
            SETUP_MODE=4
            shift # past argument
            ;;
        restore-repos)
            SETUP_MODE=5
            shift # past argument
            ;;
        update-repos)
            SETUP_MODE=6
            shift # past argument
            ;;
        update-repo-list)
            SETUP_MODE=7
            shift # past argument
            ;;
        list)
            SETUP_MODE=8
            LIST_MODE=$2
            shift # past argument
            ;;
        --gui-mode)
            GUI_MODE=1
            shift # past argument
            ;;
        --clean)
            CLEAN_FLAG=1
            shift # past argument
            ;;
        --depend)
            DEPEND_FLAG=1
            shift # past argument
            ;;
        --debug)
            SHOW_DEBUG_FLAG=1
            shift # past argument
            ;;
    *)
      shift # past argument
      ;;
  esac
done












pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

# PrintLog <LEVEL> <msg>; LEVEL: ERROR, SUCC, WARN, INFO, DEBUG, VAL
# Do not call this function directly, use PrintError, PrintSuccess, PrintWarning, PrintInfo, PrintDebug, PrintValue instead.
PrintLog ()
{
    # No GUI mode
    if [ ${GUI_MODE} -eq 0 ]; then
        status_color="\033[0m"
        reset_color="\033[0m"
        if [ "$1" == "ERROR" ]; then
            status_color="\033[1;91m" # Red
        elif [ "$1" == "SUCC" ]; then
            status_color="\033[1;92m" # Green
        elif [ "$1" == "WARN" ]; then
            status_color="\033[1;93m" # Yellow
        elif [ "$1" == "INFO" ]; then
            status_color="\033[1;94m" # Blue
        fi

        local str="${status_color}$2${reset_color}\n"
        if [ -n "${LOG_FILE_PATH}" ]; then
            printf "${str}" >> "${LOG_FILE_PATH}" 2>&1
        fi
        if [ ${SILENT_MODE} -eq 0 ]; then
            printf "${str}"
        fi
        return
    fi

    # GUI mode
    local str=""
    if [ "$1" == "VAL" ]; then
        IFS=' ' read -r -a array <<< "$2"
        str="^val"
        for i in ${array[@]}; do
            str="${str}|${i}"
        done
        str="${str}!"
    else
        str="^msg|$1|$2!"
    fi

    if [ -n "${LOG_FILE_PATH}" ]; then
        printf "%s\n" "${str}" >> "${LOG_FILE_PATH}" 2>&1
    fi
    if [ ${SILENT_MODE} -eq 0 ]; then
        printf "%s\n" "${str}"
    fi
}

PrintError ()
{
    if [ -n "$1" ]; then
        PrintLog "ERROR" "$1"
    else
        while read line
        do
            PrintLog "ERROR" "$line"
        done
    fi
}

PrintSuccess ()
{
    if [ -n "$1" ]; then
        PrintLog "SUCC" "$1"
    else
        while read line
        do
            PrintLog "SUCC" "$line"
        done
    fi
}

PrintWarning ()
{
    if [ -n "$1" ]; then
        PrintLog "WARN" "$1"
    else
        while read line
        do
            PrintLog "WARN" "$line"
        done
    fi
}

# Print info
PrintInfo ()
{
    if [ -n "$1" ]; then
        PrintLog "INFO" "$1"
    else
        while read line
        do
            PrintLog "INFO" "$line"
        done
    fi
}

PrintDebug ()
{
    local tmp_flag=${SILENT_MODE}
    if [ ${SHOW_DEBUG_FLAG} -eq 0 ]; then
        SILENT_MODE=1
    fi

    if [ -n "$1" ]; then
        PrintLog "DEBUG" "$1"
    else
        while read line
        do
            PrintLog "DEBUG" "$line"
        done
    fi
    SILENT_MODE=${tmp_flag}
}

PrintValue ()
{
    if [ -n "$1" ]; then
        PrintLog "VAL" "$1"
    else
        while read line
        do
            PrintLog "VAL" "$line"
        done
    fi
}

# ref: https://stackoverflow.com/a/47791935
# yaml file_path key
yaml ()
{
    python3 -c "import yaml;print(yaml.safe_load(open('$1'))$2)" 2>/dev/null
}

# yaml_custom_print file_path key
yaml_custom_print ()
{
    python3 -c "import yaml;s=yaml.safe_load(open('$1'))$2;print('|'.join('{}^{}'.format(k,s[k]) for k in s) if isinstance(s, dict) else s)" 2>/dev/null
}

# yaml_repo_info file_path {packages|interfaces}
yaml_repo_info ()
{
    python3 -c "import yaml;s=yaml.safe_load(open('$1'))$2;print('|'.join('{}^{}^{}'.format(r, s[r]['description'], s[r]['url']) for r in s))" 2>/dev/null
}

element_exists ()
{
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}







# Check content/scripts
CheckStartupPackage ()
{
    PrintDebug "[CheckStartupPackage] Checking the startup package..."

    if [ ! -f "${STARTUP_CONTENT_PATH}/scripts/run-internet-check.sh" ]; then
        PrintError "[CheckStartupPackage] The ${STARTUP_CONTENT_PATH}/scripts/run-internet-check.sh does not exist."
        return 1
    fi

    if [ ! -f "${STARTUP_CONTENT_PATH}/scripts/run-network-check.sh" ]; then
        PrintError "[CheckStartupPackage] The ${STARTUP_CONTENT_PATH}/scripts/run-network-check.sh does not exist."
        return 1
    fi

    PrintSuccess "[CheckStartupPackage] The startup package is correctly deployed."
    return 0
}

Init ()
{
    # Set log file path
    local date_str=$(date +%Y_%m_%d)
    LOG_FILE_PATH=${STARTUP_LOG_PATH}/${date_str}.log
    mkdir -p ${STARTUP_LOG_PATH}
    PrintDebug "

============================================================================

    [[[ Script start initializing at $(date -Iseconds) ]]]

"

    mkdir -p ${STARTUP_PKG_SCRIPTS_PATH}
    mkdir -p ${STARTUP_PKG_SERVICES_PATH}

    # Init paths
    if [ -f "${STARTUP_PATH}/config.yaml" ]; then
        local yaml_dict_str=$(yaml_custom_print "${STARTUP_PATH}/config.yaml" "")
        if [ -n "${yaml_dict_str}" ]; then
            IFS='|' read -r -a yaml_dict_arr <<< "$yaml_dict_str"
            for yaml_dict in "${yaml_dict_arr[@]}"; do
                IFS='^' read -r -a yaml_kv_arr <<< "$yaml_dict"
                if [ ${#yaml_kv_arr[@]} -ne 2 ]; then
                    PrintWarning "[Init] Invalid yaml config format: ${yaml_dict}. The format should be <key>^<value>."
                    continue
                fi

                if [ "${yaml_kv_arr[0]}" == "ROS2_WS_PATH" ]; then
                    if [[ ${yaml_kv_arr[1]:0:1} == "~" ]]; then
                        yaml_kv_arr[1]=${HOME}${yaml_kv_arr[1]:1}
                    fi
                    ROS2_WS_PATH=${yaml_kv_arr[1]}
                    ROS2_WS_SRC_PATH=${ROS2_WS_PATH}/src
                elif [ "${yaml_kv_arr[0]}" == "FTP_SERVER_PATH" ]; then
                    FTP_SERVER_PATH=${yaml_kv_arr[1]}
                elif [ "${yaml_kv_arr[0]}" == "FTP_SERVER_REPO_VERSION" ]; then
                    FTP_SERVER_REPO_VERSION=${yaml_kv_arr[1]}
                fi
            done
        fi
    fi

    if [ ! -d "${ROS2_WS_SRC_PATH}" ]; then
        PrintWarning "[CheckStartupPackage] The ${ROS2_WS_SRC_PATH} does not exist. Creating..."
        mkdir -p ${ROS2_WS_SRC_PATH}
    fi

    # Check Python3
    if [ -z "${PYTHON3_PATH}" ]; then
        PYTHON3_PATH=$(which python3)
        if [ -z "${PYTHON3_PATH}" ]; then
            PrintError "[Init] Python3 is not installed."
            return 1
        fi
    fi

    local ros_distro=NONE
    # Check Ubuntu release
    ubuntu_ver=$(lsb_release -r | grep -Po '[\d.]+')
    if [ "$ubuntu_ver" == "20.04" ]
    then
        ros_distro="foxy"
    elif [ "$ubuntu_ver" == "22.04" ]
    then
        ros_distro="humble"
    else
        PrintError "[Init] Ubuntu release not supported. ($ubuntu_ver)"
        return 1
    fi

    # Check ROS2 installation
    if [ ! -f "/opt/ros/${ros_distro}/setup.bash" ]; then
        PrintError "[Init] ROS2 distro ${ros_distro} is not installed."
        return 1
    fi

    # Check ROS2 environment variables
    source /opt/ros/${ros_distro}/setup.bash
    if [[ "${ROS_DISTRO}" != "${ros_distro}" ]]; then
        PrintError "[Init] ROS2 is not correctly sourced."
        return 1
    fi
    PrintDebug "[Init] ROS2 distro ${ros_distro} is correctly sourced."

    # Set ROS2 default share path
    ROS2_DEFAULT_SHARE_PATH=/opt/ros/${ros_distro}/share
    PrintDebug "[Init] ROS2 default share path is set to ${ROS2_DEFAULT_SHARE_PATH}."

    # Create temp directory
    mkdir -p ${STARTUP_TMP_PATH}

    PrintSuccess "[Init] The script is initialized successfully."
    return 0
}


# GetROS2WsPackageDict pkg_dict
GetROS2WsPackageDict ()
{
    PrintDebug "[GetROS2WsPackageDict] Getting the ROS2 package list under ${ROS2_WS_SRC_PATH} ..."
    local -n pkg_dict_=$1
    local pkg_xml_files=$(find ${ROS2_WS_SRC_PATH} -type f -iname package.xml)
    for pkg_xml in ${pkg_xml_files}; do
        local pkg_name=$(grep -Po "(?<=<name>)[a-z0-9_]+(?=</name>)" ${pkg_xml})
        pkg_dict_["${pkg_name}"]=$(dirname ${pkg_xml})
    done
    return 0
}


# GetRepoInfoList yaml_file_path {packages|interfaces} name_arr desc_arr url_arr
GetRepoInfoList ()
{
    local yaml_file_path_=$1
    local repo_type_=$2
    local -n name_arr_=$3
    local -n desc_arr_=$4
    local -n url_arr_=$5

    PrintDebug "[GetRepoInfoList] Getting the ${repo_type_} info from ${yaml_file_path_} ..."

    # Check repos info
    local repos_info_=$(yaml_repo_info "${yaml_file_path_}" "['${repo_type_}']")
    if [ -z "${repos_info_}" ]; then
        PrintError "[GetRepoInfoList] The ${repo_type_} info under ${yaml_file_path_} is not correctly loaded."
        return 1
    fi

    while read -r repos_info_str_; do
        # <repo_name>^<repo_desc>^<repo_url>|<repo_name>^<repo_desc>^<repo_url>|...|<repo_name>^<repo_desc>^<repo_url>
        IFS='|' read -r -a repo_info_arr_ <<< "$repos_info_str_"
        PrintDebug "$(declare -p repo_info_arr_)"
        for repo_info_ in "${repo_info_arr_[@]}"; do
            # <repo_name>^<repo_desc>^<repo_url>
            IFS='^' read -r -a repo_info_kv_ <<< "$repo_info_"
            if [ ${#repo_info_kv_[@]} -ne 3 ]; then
                PrintWarning "[GetRepoInfoList] Invalid repo info format: ${repo_info_}. The format should be <name>^<desc>^<url>."
                continue
            fi

            name_arr_+=("${repo_info_kv_[0]}")
            desc_arr_+=("${repo_info_kv_[1]}")
            url_arr_+=("${repo_info_kv_[2]}")
        done
    done <<< "${repos_info_}"

    PrintSuccess "[GetRepoInfoList] The ${repo_type_} info is correctly loaded."
    return 0
}

CheckRepoList ()
{
    PrintDebug "[CheckRepoList] Checking the repo list..."

    if [ ! -f "${STARTUP_CONTENT_PATH}/packages.yaml" ]; then
        PrintWarning "[CheckRepoList] The ${STARTUP_CONTENT_PATH}/packages.yaml does not exist. Try updating..."
        if ! UpdateRepoList; then
            PrintError "[CheckRepoList] The repo list is not correctly fetched."
            return 1
        fi
    fi

    if [ ${REPO_NEED_UPDATE} -eq 0 ]; then
        PrintSuccess "[CheckRepoList] The repo list is already updated."
        return 0
    fi

    local get_status=0
    GetRepoInfoList "${STARTUP_CONTENT_PATH}/packages.yaml" "packages" REPO_PKG_NAME_ARR REPO_PKG_DESC_ARR REPO_PKG_URL_ARR
    if [ ${#REPO_PKG_NAME_ARR[@]} -eq 0 ] || [ ${#REPO_PKG_NAME_ARR[@]} -ne ${#REPO_PKG_DESC_ARR[@]} ] || [ ${#REPO_PKG_NAME_ARR[@]} -ne ${#REPO_PKG_URL_ARR[@]} ]; then
        PrintWarning "[CheckRepoList] The package list is not correctly loaded."
        get_status=1
    fi

    GetRepoInfoList "${STARTUP_CONTENT_PATH}/packages.yaml" "interfaces" REPO_INTER_NAME_ARR REPO_INTER_DESC_ARR REPO_INTER_URL_ARR
    if [ ${#REPO_INTER_NAME_ARR[@]} -eq 0 ] || [ ${#REPO_INTER_NAME_ARR[@]} -ne ${#REPO_INTER_DESC_ARR[@]} ] || [ ${#REPO_INTER_NAME_ARR[@]} -ne ${#REPO_INTER_URL_ARR[@]} ]; then
        PrintWarning "[CheckRepoList] The interface list is not correctly loaded."
        get_status=1
    fi

    PrintDebug "$(declare -p REPO_PKG_NAME_ARR)"
    PrintDebug "$(declare -p REPO_PKG_DESC_ARR)"
    PrintDebug "$(declare -p REPO_PKG_URL_ARR)"
    PrintDebug "$(declare -p REPO_INTER_NAME_ARR)"
    PrintDebug "$(declare -p REPO_INTER_DESC_ARR)"
    PrintDebug "$(declare -p REPO_INTER_URL_ARR)"

    REPO_NEED_UPDATE=0
    if [ ${get_status} -eq 1 ]; then
        PrintWarning "[CheckRepoList] The repo list is deployed with some errors."
    else
        PrintSuccess "[CheckRepoList] The repo list is correctly deployed."
    fi
    return 0
}







# The function will create the package file under the ${STARTUP_PKG_SCRIPTS_PATH} with the provided package name and id.
CreatePackageFile ()
{
    PrintDebug "[CreatePackageFile] Creating the package file: ${PACKAGE_NAME}_${PACKAGE_ID} ..."

    if [[ "${PACKAGE_NAME}" == "NONE" ]]; then
        PrintError "[CreatePackageFile] The package name is not provided."
        return 1
    fi

    if [[ "${PACKAGE_ID}" == "NONE" || ! ${PACKAGE_ID} =~ ${VALID_PACKAGE_ID_REGEX} ]]; then
        PrintError "[CreatePackageFile] The package id is not provided or invalid."
        return 1
    fi

    local -A pkg_dict
    GetROS2WsPackageDict pkg_dict
    PrintDebug "$(declare -p pkg_dict)"

    local repo_path=""

    if element_exists "${PACKAGE_NAME}" "${!pkg_dict[@]}"; then
        repo_path=${pkg_dict["${PACKAGE_NAME}"]}
    else
        PrintError "[CreatePackageFile] The package ${PACKAGE_NAME} is not found under ${ROS2_WS_SRC_PATH}."
        return 1
    fi

    # Check the params.yaml and system.yaml
    local params_path=${repo_path}/params/params.yaml
    local system_path=${repo_path}/params/system.yaml

    if [ ! -f "${params_path}" ]; then
        PrintError "[CreatePackageFile] The ${params_path} does not exist."
        return 1
    fi

    if [ ! -f "${system_path}" ]; then
        PrintError "[CreatePackageFile] The ${system_path} does not exist."
        return 1
    fi

    # Check launch file
    local launch_path=${repo_path}/launch/launch.py
    if [ ! -f "${launch_path}" ]; then
        PrintError "[CreatePackageFile] The ${launch_path} does not exist."
        return 1
    fi

    # Create the package directory
    local pkg_dir=${STARTUP_PKG_SCRIPTS_PATH}/${PACKAGE_NAME}_${PACKAGE_ID}
    mkdir -p ${pkg_dir}

    # Copy the params.yaml and system.yaml
    cp -r ${repo_path}/params/* ${pkg_dir}

    PrintSuccess "[CreatePackageFile] The package file created at: ${pkg_dir}."
    return 0
}

# The function will run the custom script and generate service file with given package name and id.
# The function requires the sudo permission.
CreateServiceFile ()
{
    PrintDebug "[CreateServiceFile] Creating the service file: ${PACKAGE_NAME}_${PACKAGE_ID} ..."

    if [[ "${PACKAGE_NAME}" == "NONE" ]]; then
        PrintError "[CreateServiceFile] The package name is not provided."
        return 1
    fi

    if [[ "${PACKAGE_ID}" == "NONE" || ! ${PACKAGE_ID} =~ ${VALID_PACKAGE_ID_REGEX} ]]; then
        PrintError "[CreateServiceFile] The package id is not provided or invalid."
        return 1
    fi

    local pkg_script_dir=${STARTUP_PKG_SCRIPTS_PATH}/${PACKAGE_NAME}_${PACKAGE_ID}
    if [ ! -d "${pkg_script_dir}" ]; then
        PrintError "[CreateServiceFile] The ${pkg_script_dir} does not exist."
        return 1
    fi

    # Check the system.yaml
    local system_path=${pkg_script_dir}/system.yaml
    if [ ! -f "${system_path}" ]; then
        PrintError "[CreateServiceFile] The ${system_path} does not exist."
        return 1
    fi

    # Remove the old service file if exists
    RemoveServiceFile

    # Get the associative array of the ROS2 package name and path
    local -A pkg_dict
    GetROS2WsPackageDict pkg_dict
    PrintDebug "$(declare -p pkg_dict)"

    # The path of the ROS2 package
    local repo_path=""
    if element_exists "${PACKAGE_NAME}" "${!pkg_dict[@]}"; then
        repo_path=${pkg_dict["${PACKAGE_NAME}"]}
    else
        PrintError "[CreateServiceFile] The package ${PACKAGE_NAME} is not found under ${ROS2_WS_SRC_PATH}."
        return 1
    fi

    # Run the custom script if exists
    if [ -f "${repo_path}/scripts/custom.sh" ]; then
        PrintInfo "[CreateServiceFile] Found custom script at ${repo_path}/scripts/custom.sh. Running..."
        # Pass the system.yaml path and repo path to the custom script
        . ${repo_path}/scripts/custom.sh "${system_path}" "${repo_path}"
        if [ $? -ne 0 ]; then
            PrintError "[CreateServiceFile] The custom script is not correctly executed."
        else
            PrintSuccess "[CreateServiceFile] The custom script is executed successfully."
        fi
    fi

    # Then create runfile.sh determined by the 'network' scope in the system.yaml and source_env.sh for optional.

    # Get system.yaml parameters
    local interface=$(yaml ${system_path} "['network']['interface']")
    if [ -z "${interface}" ]; then
        PrintError "[CreateServiceFile] The interface is not provided in the ${system_path}."
        return 1
    fi

    # Check if the interface is valid
    local interfaces=$(ip -br link show | cut -d ' ' -f1)
    local valid_interface=0
    for i in $interfaces; do
        if [ "$i" == "${interface}" ]; then
            valid_interface=1
            break
        fi
    done

    if [ ${valid_interface} -eq 0 ]; then
        PrintError "[CreateServiceFile] The interface ${interface} is not valid."
        return 1
    fi

    # use_internet should be True or False
    local use_internet=$(yaml ${system_path} "['network']['internet_required']")
    if [ -z "${use_internet}" ]; then
        PrintError "[CreateServiceFile] The internet_required is not provided in the ${system_path}."
        return 1
    fi

    # Create runfile.sh under ${pkg_script_dir} determined by the ${use_internet}
    if [ "${use_internet}" == "True" ]; then
        cp ${STARTUP_CONTENT_PATH}/scripts/run-internet-check.sh ${pkg_script_dir}/runfile.sh
    else
        cp ${STARTUP_CONTENT_PATH}/scripts/run-network-check.sh ${pkg_script_dir}/runfile.sh
    fi

    # Append ${repo_path}/scripts/source_env.sh to the runfile.sh if it exists
    if [ -f "${repo_path}/scripts/source_env.sh" ]; then
        PrintInfo "[CreateServiceFile] Found source_env.sh under ${repo_path}/scripts. Appending to the runfile.sh..."
        echo "" >> ${pkg_script_dir}/runfile.sh
        cat ${repo_path}/scripts/source_env.sh >> ${pkg_script_dir}/runfile.sh
        echo "" >> ${pkg_script_dir}/runfile.sh
    fi

    # Finish the runfile.sh
    echo "export HOME=${HOME}" >> ${pkg_script_dir}/runfile.sh
    echo "source ${ROS2_WS_PATH}/install/setup.bash" >> ${pkg_script_dir}/runfile.sh
    echo "ros2 launch ${PACKAGE_NAME} launch.py params_file:=${pkg_script_dir}/params.yaml" >> ${pkg_script_dir}/runfile.sh
    echo "sleep 5" >> ${pkg_script_dir}/runfile.sh
    sudo chmod a+x ${pkg_script_dir}/runfile.sh
    PrintSuccess "[CreateServiceFile] The runfile.sh created at: ${pkg_script_dir}/runfile.sh."

    local service_name=${STARTUP_NAME}_${PACKAGE_NAME}_${PACKAGE_ID}
    local service_file=${STARTUP_PKG_SERVICES_PATH}/${service_name}.service
    rm -rf ${service_file} && touch ${service_file}

    local user_id=$(id -un)
    local user_group=$(id -gn)

    echo "[Unit]" > ${service_file}
    echo "Description=${service_name}" >> ${service_file}
    echo "" >> ${service_file}
    echo "[Service]" >> ${service_file}
    echo "User=${user_id}" >> ${service_file}
    echo "Group=${user_group}" >> ${service_file}
    echo "Type=simple" >> ${service_file}
    echo "ExecStart=${pkg_script_dir}/runfile.sh ${interface}" >> ${service_file}
    echo "Restart=always" >> ${service_file}
    echo "" >> ${service_file}
    echo "[Install]" >> ${service_file}
    echo "WantedBy=multi-user.target" >> ${service_file}

    # Copy service file to /etc/systemd/system and enable the service
    sudo chmod 644 ${service_file}
    sudo cp ${service_file} /etc/systemd/system
    sudo systemctl enable ${service_name}.service
    PrintSuccess "[CreateServiceFile] The service file created at: ${service_file}. The service is enabled."
    return 0
}

# The function will remove service file and delete service.
# The function requires the sudo permission.
RemoveServiceFile ()
{
    PrintDebug "[RemoveServiceFile] Removing the service file: ${PACKAGE_NAME}_${PACKAGE_ID} ..."

    if [[ "${PACKAGE_NAME}" == "NONE" ]]; then
        PrintError "[RemoveServiceFile] The package name is not provided."
        return 1
    fi

    if [[ "${PACKAGE_ID}" == "NONE" || ! ${PACKAGE_ID} =~ ${VALID_PACKAGE_ID_REGEX} ]]; then
        PrintError "[RemoveServiceFile] The package id is not provided or invalid."
        return 1
    fi

    local service_name=${STARTUP_NAME}_${PACKAGE_NAME}_${PACKAGE_ID}

    if sudo systemctl list-units | grep -Foq "${service_name}.service"; then
        sudo systemctl stop ${service_name} > /dev/null 2>&1
        sudo systemctl disable ${service_name} > /dev/null 2>&1
        sudo rm /etc/systemd/system/${service_name}.service > /dev/null 2>&1
        PrintSuccess "[RemoveServiceFile] The service ${service_name} is disabled and removed."
    fi

    # Remove the service file and runfile.sh
    rm -rf ${STARTUP_PKG_SERVICES_PATH}/${service_name}.service
    rm -rf ${STARTUP_PKG_SCRIPTS_PATH}/${PACKAGE_NAME}_${PACKAGE_ID}/runfile.sh
    PrintSuccess "[RemoveServiceFile] The service file and runfile.sh are removed successfully."
    return 0
}

# The function will call the RemoveServiceFile() and remove the package directory.
# The function requires the sudo permission.
RemovePackageFile ()
{
    PrintDebug "[RemovePackageFile] Removing the package file: ${PACKAGE_NAME}_${PACKAGE_ID} ..."

    if [[ "${PACKAGE_NAME}" == "NONE" ]]; then
        PrintError "[RemovePackageFile] The package name is not provided."
        return 1
    fi

    if [[ "${PACKAGE_ID}" == "NONE" || ! ${PACKAGE_ID} =~ ${VALID_PACKAGE_ID_REGEX} ]]; then
        PrintError "[RemovePackageFile] The package id is not provided or invalid."
        return 1
    fi

    RemoveServiceFile
    rm -rf ${STARTUP_PKG_SCRIPTS_PATH}/${PACKAGE_NAME}_${PACKAGE_ID}
    PrintSuccess "[RemovePackageFile] The package file is removed successfully."
    return 0
}

# The function will build ROS2 package under ${ROS2_WS_SRC_PATH} accroding to the ${STARTUP_PKG_SCRIPTS_PATH}
BuildPackage ()
{
    PrintDebug "[BuildPackage] Building the packages..."

    # Get the package list under ${ROS2_WS_SRC_PATH}
    local -A pkg_dict
    GetROS2WsPackageDict pkg_dict
    PrintDebug "$(declare -p pkg_dict)"

    # Get required package list under ${STARTUP_PKG_SCRIPTS_PATH}
    local selected_pkg_set=()

    # Install dependencies
    local apt_installed_list=$(apt list --installed 2>/dev/null)
    local pip_installed_list=$(${PYTHON3_PATH} -m pip list 2>/dev/null)

    local pkg_launcher_paths=$(find ${STARTUP_PKG_SCRIPTS_PATH} -maxdepth 1 -type d)
    for pkg_launcher_path in ${pkg_launcher_paths}; do
        # Get the package name from the directory name: <package_name>_<id>.
        local pkg_name=$(basename ${pkg_launcher_path} | grep -Po '^[a-z0-9_]+(?=_.*$)')
        if [ -z "${pkg_name}" ]; then continue; fi

        # Check if the package exists under ${ROS2_WS_SRC_PATH}
        if ! element_exists "${pkg_name}" "${!pkg_dict[@]}"; then
            PrintWarning "[BuildPackage][${pkg_name}] The package is not found under ${ROS2_WS_SRC_PATH} ."
            continue
        fi

        # Prevent duplicate package
        if element_exists "${pkg_name}" "${selected_pkg_set[@]}"; then continue; fi

        # Add package name to set
        selected_pkg_set+=("${pkg_name}")

        # Dependence list file localtion (under ${ROS2_WS_SRC_PATH}/<package_name>/)
        local repo_path=${pkg_dict["${pkg_name}"]}
        local apt_install_list=()
        local pip_install_list=()

        # Check apt install dependencies
        if [ -f "${repo_path}/requirements_apt.txt" ]; then
            PrintInfo "[BuildPackage][${pkg_name}] Found requirements_apt.txt under ${repo_path} ."

            # Check last character of the file, if not empty, add a new line.
            cp ${repo_path}/requirements_apt.txt ${STARTUP_TMP_PATH}/requirements_apt.txt
            if [ ! -z "$(tail -c 1 ${STARTUP_TMP_PATH}/requirements_apt.txt)" ]; then
                echo "" >> ${STARTUP_TMP_PATH}/requirements_apt.txt
            fi

            while read -r line; do
                if [ -z "${line}" ]; then continue; fi
                if [[ $apt_installed_list == *"$line"* && ${DEPEND_FLAG} -eq 0 ]]; then
                    continue
                fi
                apt_install_list+=("$line")
            done < ${STARTUP_TMP_PATH}/requirements_apt.txt

            # Remove the temporary file
            rm -rf ${STARTUP_TMP_PATH}/requirements_apt.txt
        fi
        PrintDebug "$(declare -p apt_install_list)"

        # Check pip install dependencies
        if [ -f "${repo_path}/requirements_pip.txt" ]; then
            PrintInfo "[BuildPackage][${pkg_name}] Found requirements_pip.txt under ${repo_path} ."

            # Check last character of the file, if not empty, add a new line.
            cp ${repo_path}/requirements_pip.txt ${STARTUP_TMP_PATH}/requirements_pip.txt
            if [ ! -z "$(tail -c 1 ${STARTUP_TMP_PATH}/requirements_pip.txt)" ]; then
                echo "" >> ${STARTUP_TMP_PATH}/requirements_pip.txt
            fi

            while read -r line; do
                if [ -z "${line}" ]; then continue; fi
                if [[ $pip_installed_list == *"$line"* && ${DEPEND_FLAG} -eq 0 ]]; then
                    continue
                fi
                pip_install_list+=("$line")
            done < ${STARTUP_TMP_PATH}/requirements_pip.txt

            # Remove the temporary file
            rm -rf ${STARTUP_TMP_PATH}/requirements_pip.txt
        fi
        PrintDebug "$(declare -p pip_install_list)"

        # Install apt dependencies
        if [ ${#apt_install_list[@]} -eq 0 ]; then
            PrintSuccess "[BuildPackage][${pkg_name}] No new apt dependencies to install."
        else
            PrintInfo "[BuildPackage][${pkg_name}] Installing the apt dependencies..."
            sudo apt install -y ${apt_install_list[@]} 2>&1 | PrintDebug
            if [ $? -ne 0 ]; then
                PrintError "[BuildPackage][${pkg_name}] The apt dependencies are not correctly installed."
            else
                PrintSuccess "[BuildPackage][${pkg_name}] The apt dependencies are installed successfully."
            fi
        fi

        # Install pip dependencies
        if [ ${#pip_install_list[@]} -eq 0 ]; then
            PrintSuccess "[BuildPackage][${pkg_name}] No new pip dependencies to install."
        else
            PrintInfo "[BuildPackage][${pkg_name}] Installing the pip dependencies..."
            ${PYTHON3_PATH} -m pip install ${pip_install_list[@]} 2>&1 | PrintDebug
            if [ $? -ne 0 ]; then
                PrintError "[BuildPackage][${pkg_name}] The pip dependencies are not correctly installed."
            else
                PrintSuccess "[BuildPackage][${pkg_name}] The pip dependencies are installed successfully."
            fi
        fi

        # Run before build script
        if [ -f "${repo_path}/scripts/script_before_build.sh" ]; then
            PrintInfo "[BuildPackage][${pkg_name}] Found script_before_build.sh under ${repo_path}/scripts . Running..."
            # Pass the repo path to the script.
            . ${repo_path}/scripts/script_before_build.sh ${repo_path} 2>&1 | PrintDebug
            if [ $? -ne 0 ]; then
                PrintError "[BuildPackage][${pkg_name}] The script_before_build.sh is not correctly executed."
            else
                PrintSuccess "[BuildPackage][${pkg_name}] The script_before_build.sh is executed successfully."
            fi
        fi
    done

    # Build the ROS2 package
    local build_path=(${ROS2_WS_PATH}/build)
    local inst_path=(${ROS2_WS_PATH}/install)
    local log_path=(${ROS2_WS_PATH}/log)
    if [ ${CLEAN_FLAG} -eq 1 ]; then
        rm -rf ${build_path} ${inst_path} ${log_path}
    fi

    local pkg_str=$(echo "${selected_pkg_set[@]} ${REPO_INTER_NAME_ARR[@]}") # Add the interface package. Not good enough but works.
    PrintInfo "[BuildPackage] Building the package: [${pkg_str}]"
    if colcon --log-base ${log_path} build --cmake-args -DPython3_EXECUTABLE="${PYTHON3_PATH}" --build-base ${build_path} --install-base ${inst_path} --base-paths ${ROS2_WS_PATH} --packages-select ${pkg_str} --symlink-install 2>&1 | PrintDebug; then
        PrintSuccess "[BuildPackage] The package is built successfully."
    else
        PrintError "[BuildPackage] The package is not built successfully."
        return 1
    fi

    # Run after build script
    for pkg_name in ${selected_pkg_set[@]}; do
        local repo_path=${pkg_dict["${pkg_name}"]}
        if [ -f "${repo_path}/scripts/script_after_build.sh" ]; then
            PrintInfo "[BuildPackage][${pkg_name}] Found script_after_build.sh under ${repo_path}/scripts . Running..."
            # Pass the repo path to the script.
            . ${repo_path}/scripts/script_after_build.sh ${repo_path} 2>&1 | PrintDebug
            if [ $? -ne 0 ]; then
                PrintError "[BuildPackage][${pkg_name}] The script_after_build.sh is not correctly executed."
            else
                PrintSuccess "[BuildPackage][${pkg_name}] The script_after_build.sh is executed successfully."
            fi
        fi
    done
    return 0
}

# The function will restore the repos to the current commit.
RestoreRepos ()
{
    PrintDebug "[RestoreRepos] Restoring the repos to the current commit..."

    CheckRepoList
    if [ $? -ne 0 ]; then
        PrintError "[RestoreRepos] The repo list is not correctly deployed."
        return 1
    fi

    local repos_name=()
    repos_name+=("${REPO_PKG_NAME_ARR[@]}")
    repos_name+=("${REPO_INTER_NAME_ARR[@]}")
    for repo_name in ${repos_name[@]}; do
        # Check if the repo is a directory and exist .git directory
        if [ ! -d "${ROS2_WS_SRC_PATH}/${repo_name}/.git" ]; then
            PrintWarning "[RestoreRepos] The repo ${repo_name} does not exist git control."
            continue
        fi
        pushd ${ROS2_WS_SRC_PATH}/${repo_name}
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git restore --staged . --quiet
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git restore . --quiet
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git clean -fd --quiet
        popd
    done

    PrintSuccess "[RestoreRepos] The repos are restored to the current commit."
    return 0
}

# Function use git clone and pull to update the repos.
UpdateRepos ()
{
    PrintDebug "[UpdateRepos] Updating the repos..."

    CheckRepoList
    if [ $? -ne 0 ]; then
        PrintError "[UpdateRepos] The repo list is not correctly deployed."
        return 1
    fi
    # Read list to array
    local repos_name=()
    repos_name+=("${REPO_PKG_NAME_ARR[@]}")
    repos_name+=("${REPO_INTER_NAME_ARR[@]}")

    local repos_url=()
    repos_url+=("${REPO_PKG_URL_ARR[@]}")
    repos_url+=("${REPO_INTER_URL_ARR[@]}")

    local len=${#repos_name[@]}
    for (( i=0; i<${len}; i++ )); do
        local repo_name=${repos_name[$i]}
        local repo_url=${repos_url[$i]}
        # Check if the repo is a directory and exist .git directory
        if [ ${CLEAN_FLAG} -eq 1 ] || [ ! -d "${ROS2_WS_SRC_PATH}/${repo_name}/.git" ]; then
            rm -rf ${ROS2_WS_SRC_PATH}/${repo_name}
            git clone ${repo_url} ${ROS2_WS_SRC_PATH}/${repo_name} --quiet
            if [ $? -ne 0 ]; then
                PrintWarning "[UpdateRepos] The repo ${repo_name} is not correctly cloned."
            fi
            continue
        fi

        pushd ${ROS2_WS_SRC_PATH}/${repo_name}
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git add .
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git pull --quiet
        popd
    done

    PrintSuccess "[UpdateRepos] The repos are updated successfully."
    return 0
}

# The function will update the packages.yaml from the ftp server.
UpdateRepoList ()
{
    local ftp_server_path=${FTP_SERVER_PATH}/${FTP_SERVER_REPO_VERSION}
    PrintDebug "[UpdateRepoList] Fetching the latest repo list from the ${FTP_SERVER_PATH} ..."

    if wget -q -O ${STARTUP_CONTENT_PATH}/packages.yaml ${ftp_server_path}/packages.yaml; then
        PrintSuccess "[UpdateRepoList] The repo list is fetched successfully."
        REPO_NEED_UPDATE=1
    else
        PrintError "[UpdateRepoList] The repo list is not fetched successfully."
        return 1
    fi
    return 0
}

# The function will list the package launcher and repos.
List ()
{
    PrintDebug "[List] Listing the package launcher and repos..."

    # ${LIST_MODE}: all, repos, scripts, services
    if [ "${LIST_MODE}" != "all" ] && [ "${LIST_MODE}" != "repos" ] && [ "${LIST_MODE}" != "scripts" ] && [ "${LIST_MODE}" != "services" ]; then
        PrintError "[List] The list mode is not valid."
        return 1
    fi

    # Set the silent mode
    SILENT_MODE=1

    # Get the package list under ${ROS2_WS_SRC_PATH}
    local -A pkg_dict
    GetROS2WsPackageDict pkg_dict
    PrintDebug "$(declare -p pkg_dict)"

    # The two dicts describe the package launcher status. Package launcher: <package_name>_<id>
    # Relation between the package and the repo.
    local -A pkg_repo_dict # { <package_name>_<id> : <repo_name> }
    # Whether package launcher have service file.
    local -A pkg_status_dict # { <package_name>_<id> : {0|1} }

    local pkg_launcher_paths=$(find ${STARTUP_PKG_SCRIPTS_PATH} -maxdepth 1 -type d)
    for pkg_launcher_path in ${pkg_launcher_paths}; do
        # Get the package name from the directory name: <package_name>_<id>.
        local pkg_launcher_name=$(basename ${pkg_launcher_path})
        local pkg_name=$(echo ${pkg_launcher_name} | grep -Po '^[a-z0-9_]+(?=_.*$)')
        if [ -z "${pkg_name}" ]; then continue; fi

        # Check if the package exists under ${ROS2_WS_SRC_PATH}
        if ! element_exists "${pkg_name}" "${!pkg_dict[@]}"; then
            PrintWarning "[List][${pkg_name}] The package is not found under ${ROS2_WS_SRC_PATH} ."
            continue
        fi
        pkg_repo_dict["${pkg_launcher_name}"]="${pkg_name}"

        # Check if the service file exists
        if [ -f "${STARTUP_PKG_SERVICES_PATH}/${STARTUP_NAME}_${pkg_launcher_name}.service" ]; then
            pkg_status_dict["${pkg_launcher_name}"]=1
        else
            pkg_status_dict["${pkg_launcher_name}"]=0
        fi
    done

    SILENT_MODE=0

    # Print list for 'scripts' and 'services' mode.
    if [ "${LIST_MODE}" == "scripts" ]; then
        declare -p pkg_status_dict
        PrintValue "$(echo ${!pkg_status_dict[@]})"
        return 0
    elif [ "${LIST_MODE}" == "services" ]; then
        local arr_=()
        for pkg_launcher_name in "${!pkg_status_dict[@]}"; do
            if [ ${pkg_status_dict["${pkg_launcher_name}"]} -eq 1 ]; then
                arr_+=("${pkg_launcher_name}")
            fi
        done
        if [ ${#arr_[@]} -gt 0 ]; then
            PrintValue "$(echo ${arr_[@]})"
        fi
        return 0
    fi

    ######## The following process requires the repo list ########

    SILENT_MODE=1
    # Check repo list
    CheckRepoList
    SILENT_MODE=0

    if [ $? -ne 0 ]; then
        PrintError "[List] The repo list is not correctly deployed."
        return 1
    fi

    # The two dicts are the union of the keys of the pkg_dict, REPO_PKG_NAME_ARR and REPO_INTER_NAME_ARR.
    local -A repo_tracked_dict # { <repo_name> : {0|1} }
    local -A repo_fetched_dict # { <repo_name> : {0|1} }

    # repos in ${ROS2_WS_SRC_PATH}
    for repo_name in "${!pkg_dict[@]}"; do
        if element_exists "${repo_name}" "${REPO_PKG_NAME_ARR[@]}" || element_exists "${repo_name}" "${REPO_INTER_NAME_ARR[@]}"; then
            # The repo under ${ROS2_WS_SRC_PATH} is tracked in the repo list and fetched.
            repo_tracked_dict["${repo_name}"]=1
            repo_fetched_dict["${repo_name}"]=1
        else
            # The repo under ${ROS2_WS_SRC_PATH} is not tracked in the repo list.
            repo_tracked_dict["${repo_name}"]=0
            repo_fetched_dict["${repo_name}"]=0
        fi
    done

    # repos in ${REPO_PKG_NAME_ARR} and ${REPO_INTER_NAME_ARR}
    for repo_name in "${REPO_PKG_NAME_ARR[@]}" "${REPO_INTER_NAME_ARR[@]}"; do
        if ! element_exists "${repo_name}" "${!pkg_dict[@]}"; then
            # The repo in the repo list is not found under ${ROS2_WS_SRC_PATH}.
            repo_tracked_dict["${repo_name}"]=1
            repo_fetched_dict["${repo_name}"]=0
        fi
    done

    # Print list for 'all' and 'repos' mode.
    if [ "${LIST_MODE}" == "repos" ]; then
        for repo_name in "${!repo_tracked_dict[@]}"; do
            PrintValue "${repo_name} ${repo_tracked_dict["${repo_name}"]} ${repo_fetched_dict["${repo_name}"]}"
        done
    elif [ "${LIST_MODE}" == "all" ]; then
        local printed_repo_name=()
        for pkg_launcher_name in "${!pkg_status_dict[@]}"; do
            local pkg_status=${pkg_status_dict["${pkg_launcher_name}"]}
            local repo_name=${pkg_repo_dict["${pkg_launcher_name}"]}
            local repo_tracked=${repo_tracked_dict["${repo_name}"]}
            local repo_fetched=${repo_fetched_dict["${repo_name}"]}
            if ! element_exists "${repo_name}" "${printed_repo_name[@]}"; then
                printed_repo_name+=("${repo_name}")
            fi
            PrintValue "${pkg_launcher_name} ${pkg_status} ${repo_name} ${repo_tracked} ${repo_fetched}"
        done

        for repo_name in "${!repo_tracked_dict[@]}"; do
            if element_exists "${repo_name}" "${printed_repo_name[@]}"; then
                continue
            fi
            local repo_tracked=${repo_tracked_dict["${repo_name}"]}
            local repo_fetched=${repo_fetched_dict["${repo_name}"]}
            PrintValue "- 0 ${repo_name} ${repo_tracked} ${repo_fetched}"
        done
    fi

    return 0
}




####################################################################################################

# Check the startup package
CheckStartupPackage
if [ $? -ne 0 ]; then
    PrintError "[Script] The startup package is not correctly deployed."
    return 1
fi

# Set log file, check environment and ROS2 installation
Init
if [ $? -ne 0 ]; then
    PrintError "[Script] The script is not correctly initialized."
    return 1
fi

# 0: create, 1: create-service, 2: remove-service, 3: remove, 4: build, 5: restore-repos, 6: update-repos, 7: update-repo-list, 8: list
PrintDebug "[Script] Setup mode: ${SETUP_MODE}"



if [ ${SETUP_MODE} -eq 0 ]; then
    CreatePackageFile
elif [ ${SETUP_MODE} -eq 1 ]; then
    CreateServiceFile
elif [ ${SETUP_MODE} -eq 2 ]; then
    RemoveServiceFile
elif [ ${SETUP_MODE} -eq 3 ]; then
    RemovePackageFile
elif [ ${SETUP_MODE} -eq 4 ]; then
    BuildPackage
elif [ ${SETUP_MODE} -eq 5 ]; then
    RestoreRepos
elif [ ${SETUP_MODE} -eq 6 ]; then
    UpdateRepos
elif [ ${SETUP_MODE} -eq 7 ]; then
    UpdateRepoList
elif [ ${SETUP_MODE} -eq 8 ]; then
    List
fi


