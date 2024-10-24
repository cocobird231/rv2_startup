#!/bin/bash

HOME_PATH=${HOME}
STARTUP_NAME=rv2_startup

STARTUP_PATH=${HOME_PATH}/${STARTUP_NAME}
STARTUP_CONTENT_PATH=${STARTUP_PATH}/content
STARTUP_LOG_PATH=${STARTUP_PATH}/log
STARTUP_PKG_SCRIPTS_PATH=${STARTUP_PATH}/launch/scripts
STARTUP_PKG_SERVICES_PATH=${STARTUP_PATH}/launch/services
STARTUP_TMP_PATH=${STARTUP_PATH}/.tmp

VALID_PACKAGE_REGEX='[a-z0-9_-]+'
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
SHARE_PKG_NAME_REGEX_LIST=()


# Input parameters
PACKAGE_NAME=NONE
PACKAGE_ID=NONE
PACKAGE_NO_LAUNCH=0
SETUP_MODE=-1 # 0: create, 1: create-service, 2: remove-service, 3: remove, 4: build, 5: restore-repos, 6: update-repos, 7: update-repo-list, 8: list
LIST_MODE=NONE # all, pkgs, scripts, services.
# Package status:
# 8 4 2 1
# - - - 0: Package not in local src.
# - - - 1: Pacakge in local src.
# - - 0 -: Package not in packages.yaml.
# - - 1 -: Package in packages.yaml. (tracked)

# - - 0 0: Package in global share.
# - - 0 1: Custom package in local src.
# - - 1 0: Package tracked but not fetched.
# - - 1 1: Package fetched.

# Set by input parameters
ALL_FLAG=0
CLEAN_FLAG=0
DEPEND_FLAG=0
GUI_MODE_FLAG=0
SHOW_DEBUG_FLAG=0

# Set by the script
SILENT_MODE=0

unset REPO_DESC_ARR REPO_URL_ARR PKG_REPO_ARR
declare -A REPO_DESC_ARR # { <repo_name> : <repo_desc> }
declare -A REPO_URL_ARR # { <repo_name> : <repo_url> }
declare -A PKG_REPO_ARR # { <pkg_name> : <repo_name> }

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
        --pkg-no-launch)
            PACKAGE_NO_LAUNCH=1
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
        --all)
            ALL_FLAG=1
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
        --gui-mode)
            GUI_MODE_FLAG=1
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
PrintLog () {
    # No GUI mode
    if [ ${GUI_MODE_FLAG} -eq 0 ]; then
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

PrintError () {
    if [ -n "$1" ]; then
        PrintLog "ERROR" "$1"
    else
        while read line
        do
            PrintLog "ERROR" "$line"
        done
    fi
}

PrintSuccess () {
    if [ -n "$1" ]; then
        PrintLog "SUCC" "$1"
    else
        while read line
        do
            PrintLog "SUCC" "$line"
        done
    fi
}

PrintWarning () {
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
PrintInfo () {
    if [ -n "$1" ]; then
        PrintLog "INFO" "$1"
    else
        while read line
        do
            PrintLog "INFO" "$line"
        done
    fi
}

PrintDebug () {
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

PrintValue () {
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
    python3 -c "import yaml;s=yaml.safe_load(open('$1'))$2;print('|'.join('{}\`{}'.format(k,s[k]) for k in s) if isinstance(s, dict) else s)" 2>/dev/null
}

# yaml_repo_info file_path {packages}
yaml_repo_info ()
{
    python3 -c "import yaml;s=yaml.safe_load(open('$1'))$2;print('|'.join('{}\`{}\`{}\`{}'.format(k, s[k]['description'], s[k]['url'], '\`'.join(s[k]['packages'])) for k in s))" 2>/dev/null
}

element_exists ()
{
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}







# Check content/scripts
CheckStartupPackage () {
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

Init () {
    # Set log file path
    local date_str=$(date +%Y_%m_%d)
    LOG_FILE_PATH=${STARTUP_LOG_PATH}/${date_str}.log
    mkdir -p ${STARTUP_LOG_PATH}
    PrintDebug "


        [[[ Script start initializing at $(date -Iseconds) ]]]"

    mkdir -p ${STARTUP_PKG_SCRIPTS_PATH}
    mkdir -p ${STARTUP_PKG_SERVICES_PATH}
    mkdir -p ${STARTUP_TMP_PATH}

    # Init paths
    if [ -f "${STARTUP_PATH}/config.yaml" ]; then
        # Environment setup
        local yaml_dict_str=$(yaml_custom_print "${STARTUP_PATH}/config.yaml" "['ENVIRONMENT_SETUP']")
        if [ -n "${yaml_dict_str}" ]; then
            IFS='|' read -r -a yaml_dict_arr <<< "$yaml_dict_str"
            for yaml_dict in "${yaml_dict_arr[@]}"; do
                IFS='\`' read -r -a yaml_kv_arr <<< "$yaml_dict"
                if [ ${#yaml_kv_arr[@]} -ne 2 ]; then
                    PrintWarning "[Init] Invalid yaml config format: ${yaml_dict}. The format should be <key>\`<value>."
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

        # Share package name regex list
        yaml_dict_str=$(yaml_custom_print "${STARTUP_PATH}/config.yaml" "['ROS2_SHARE_PKG_NAME_REGEX']")
        if [ -n "${yaml_dict_str}" ]; then
            IFS='|' read -r -a yaml_dict_arr <<< "$yaml_dict_str"
            for yaml_dict in "${yaml_dict_arr[@]}"; do
                IFS='\`' read -r -a yaml_kv_arr <<< "$yaml_dict"
                if [ ${#yaml_kv_arr[@]} -ne 2 ]; then
                    PrintWarning "[Init] Invalid yaml config format: ${yaml_dict}. The format should be <key>\`<value>."
                    continue
                fi
                SHARE_PKG_NAME_REGEX_LIST+=("${yaml_kv_arr[1]}")
            done
        fi
    fi

    PrintDebug "$(declare -p ROS2_WS_SRC_PATH)"
    PrintDebug "$(declare -p FTP_SERVER_PATH)"
    PrintDebug "$(declare -p FTP_SERVER_REPO_VERSION)"
    PrintDebug "$(declare -p SHARE_PKG_NAME_REGEX_LIST)"

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
    local ubuntu_ver=$(lsb_release -r | grep -Po '[\d.]+')
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
    if [ ! -d "/opt/ros/${ros_distro}/share" ]; then
        PrintError "[Init] ROS2 default share path is not found."
        return 1
    fi
    ROS2_DEFAULT_SHARE_PATH=/opt/ros/${ros_distro}/share
    PrintDebug "$(declare -p ROS2_DEFAULT_SHARE_PATH)"

    PrintSuccess "[Init] The script is initialized successfully."
    return 0
}


# GetROS2PackageDict pkg_path_dict pkg_islocal_dict
GetROS2PackageDict () {
    local -n pkg_path_dict_=$1
    local -n pkg_islocal_dict_=$2

    PrintDebug "[GetROS2PackageDict] Search ROS2 package under ${ROS2_WS_SRC_PATH} ..."
    local pkg_xml_files=$(find ${ROS2_WS_SRC_PATH} -type f -iname package.xml)
    for pkg_xml in ${pkg_xml_files}; do
        local pkg_name=$(grep -Po "(?<=<name>)${VALID_PACKAGE_REGEX}(?=</name>)" ${pkg_xml})
        pkg_path_dict_["${pkg_name}"]=$(dirname ${pkg_xml})
        pkg_islocal_dict_["${pkg_name}"]=1
    done

    PrintDebug "[GetROS2PackageDict] Search ROS2 package under ${ROS2_DEFAULT_SHARE_PATH} ..."
    pkg_xml_files=$(find ${ROS2_DEFAULT_SHARE_PATH} -maxdepth 2 -type f -iname package.xml)
    for pkg_xml in ${pkg_xml_files}; do
        local pkg_name=$(grep -Po "(?<=<name>)${VALID_PACKAGE_REGEX}(?=</name>)" ${pkg_xml})
        for regex in "${SHARE_PKG_NAME_REGEX_LIST[@]}"; do
            if [[ "${pkg_name}" =~ ${regex} ]]; then
                pkg_path_dict_["${pkg_name}"]=$(dirname ${pkg_xml})
                pkg_islocal_dict_["${pkg_name}"]=0
                break
            fi
        done
    done
    return 0
}

CheckRepoList () {
    PrintDebug "[CheckRepoList] Checking the repo list..."
    local yaml_file_path=${STARTUP_CONTENT_PATH}/packages.yaml
    if [ ! -f "${yaml_file_path}" ]; then
        PrintWarning "[CheckRepoList] The ${yaml_file_path} does not exist. Try updating..."
        if ! UpdateRepoList; then
            PrintError "[CheckRepoList] The repo list is not correctly fetched."
            return 1
        fi
    fi

    local ret_status=0
    local yaml_str=$(yaml_repo_info "${yaml_file_path}" "['packages']")
    if [ -n "${yaml_str}" ]; then
        IFS='|' read -r -a repo_arr <<< "${yaml_str}"
        for repo in "${repo_arr[@]}"; do
            IFS='\`' read -r -a repo_info_arr <<< "${repo}" # repo_name, repo_desc, repo_url, packages, ...
            REPO_DESC_ARR["${repo_info_arr[0]}"]="${repo_info_arr[1]}"
            REPO_URL_ARR["${repo_info_arr[0]}"]="${repo_info_arr[2]}"
            for ((i=3; i<${#repo_info_arr[@]}; i++)); do
                PKG_REPO_ARR[${repo_info_arr[$i]}]=${repo_info_arr[0]}
            done
        done
    else
        PrintError "[CheckRepoList] The repo list under ${yaml_file_path} is not correctly loaded."
        ret_status=1
    fi

    PrintDebug "$(declare -p REPO_DESC_ARR)"
    PrintDebug "$(declare -p REPO_URL_ARR)"
    PrintDebug "$(declare -p PKG_REPO_ARR)"
    return ${ret_status}
}







# The function will create the package file under the ${STARTUP_PKG_SCRIPTS_PATH} with the provided package name and id.
CreatePackageFile () {
    PrintDebug "[CreatePackageFile] Creating the package file: ${PACKAGE_NAME}_${PACKAGE_ID} ..."

    if [[ "${PACKAGE_NAME}" == "NONE" ]]; then
        PrintError "[CreatePackageFile] The package name is not provided."
        return 1
    fi

    if [[ "${PACKAGE_ID}" == "NONE" || ! ${PACKAGE_ID} =~ ${VALID_PACKAGE_ID_REGEX} ]] && [ ${PACKAGE_NO_LAUNCH} -eq 0 ] ; then
        PrintError "[CreatePackageFile] The package id is not provided or invalid."
        return 1
    fi

    local -A pkg_path_dict
    local -A pkg_islocal_dict
    GetROS2PackageDict pkg_path_dict pkg_islocal_dict
    PrintDebug "$(declare -p pkg_path_dict)"
    PrintDebug "$(declare -p pkg_islocal_dict)"

    local repo_path=""

    if element_exists "${PACKAGE_NAME}" "${!pkg_path_dict[@]}"; then
        repo_path=${pkg_path_dict["${PACKAGE_NAME}"]}
    else
        PrintError "[CreatePackageFile] The package ${PACKAGE_NAME} is not found under ${ROS2_WS_SRC_PATH} or ${ROS2_DEFAULT_SHARE_PATH} ."
        return 1
    fi

    if [ ${PACKAGE_NO_LAUNCH} -eq 1 ]; then
        local pkg_launcher_path=${STARTUP_PKG_SCRIPTS_PATH}/${PACKAGE_NAME}_nolaunch
        mkdir -p ${pkg_launcher_path}
        PrintSuccess "[CreatePackageFile] The non-launchable package file created at: ${pkg_launcher_path}."
        return 0
    fi

    # Check the launch files
    local launch_files=($(find ${repo_path}/launch -type f -name "*.py"))
    if [ ${#launch_files[@]} -eq 0 ]; then
        PrintError "[CreatePackageFile] The launch file does not exist under ${repo_path}/launch."
        return 1
    else
        PrintDebug "[CreatePackageFile] Found launch files: ${launch_files[@]}."
    fi

    # Check the params.yaml and system.yaml
    local params_files=($(find ${repo_path}/params -type f -name "*.yaml" 2>/dev/null))
    local use_config=0

    if [ ${#params_files[@]} -eq 0 ]; then
        PrintWarning "[CreatePackageFile] The parameter file does not exist under ${repo_path}/params."
        params_files=($(find ${repo_path}/config -type f -name "*.yaml" 2>/dev/null))
        if [ ${#params_files[@]} -eq 0 ]; then
            PrintError "[CreatePackageFile] The config file does not exist under ${repo_path}/config."
            return 1
        else
            PrintWarning "[CreatePackageFile] The config file is used instead of the parameter file."
            use_config=1
        fi
    fi

    # Create the package launcher directory
    local pkg_launcher_path=${STARTUP_PKG_SCRIPTS_PATH}/${PACKAGE_NAME}_${PACKAGE_ID}
    mkdir -p ${pkg_launcher_path}

    # Copy params or config files to the package directory
    if [ ${use_config} -eq 1 ]; then
        cp -r ${repo_path}/config/* ${pkg_launcher_path}
        touch ${pkg_launcher_path}/.config # Create a flag file to indicate the config files are used.
    else
        cp -r ${repo_path}/params/* ${pkg_launcher_path}
    fi

    local system_path=${repo_path}/params/system.yaml
    if [ ! -f "${system_path}" ]; then
        PrintWarning "[CreatePackageFile] The ${system_path} does not exist. Create a new one under ${pkg_launcher_path} ..."
        local system_file=${pkg_launcher_path}/system.yaml
        rm -rf ${system_file} && touch ${system_file}
        echo "launch:" >> ${system_file}
        echo "    params: $(basename ${params_files[0]})" >> ${system_file}
        echo "    launch: $(basename ${launch_files[0]})" >> ${system_file}
        echo "    use_root: false" >> ${system_file}
        echo "network:" >> ${system_file}
        local interfaces=($(ip addr show scope link | grep -P 'BROADCAST,MULTICAST,UP,LOWER_UP' | cut -d ':' -f2 | tr -d ' '))
        echo "    interface: ${interfaces[0]:-}" >> ${system_file}
        echo "    internet_required: false" >> ${system_file}
    fi

    PrintSuccess "[CreatePackageFile] The package file created at: ${pkg_launcher_path}."
    return 0
}

# The function will run the custom script and generate service file with given package name and id.
# The function requires the sudo permission.
CreateServiceFile () {
    PrintDebug "[CreateServiceFile] Creating the service file: ${PACKAGE_NAME}_${PACKAGE_ID} ..."

    if [[ "${PACKAGE_NAME}" == "NONE" ]]; then
        PrintError "[CreateServiceFile] The package name is not provided."
        return 1
    fi

    if [[ "${PACKAGE_ID}" == "NONE" || ! ${PACKAGE_ID} =~ ${VALID_PACKAGE_ID_REGEX} ]]; then
        PrintError "[CreateServiceFile] The package id is not provided or invalid."
        return 1
    fi

    local pkg_launcher_path=${STARTUP_PKG_SCRIPTS_PATH}/${PACKAGE_NAME}_${PACKAGE_ID}
    if [ ! -d "${pkg_launcher_path}" ]; then
        PrintError "[CreateServiceFile] The ${pkg_launcher_path} does not exist."
        return 1
    fi

    # Check the system.yaml
    local system_path=${pkg_launcher_path}/system.yaml
    if [ ! -f "${system_path}" ]; then
        PrintError "[CreateServiceFile] The ${system_path} does not exist."
        return 1
    fi

    local use_config=0
    if [ -f "${pkg_launcher_path}/.config" ]; then
        use_config=1
    fi

    # Remove the old service file if exists
    RemoveServiceFile

    # Get the associative array of the ROS2 package name and path
    local -A pkg_path_dict
    local -A pkg_islocal_dict
    GetROS2PackageDict pkg_path_dict pkg_islocal_dict
    PrintDebug "$(declare -p pkg_path_dict)"
    PrintDebug "$(declare -p pkg_islocal_dict)"

    # The path of the ROS2 package
    local repo_path=""
    if element_exists "${PACKAGE_NAME}" "${!pkg_path_dict[@]}"; then
        repo_path=${pkg_path_dict["${PACKAGE_NAME}"]}
    else
        PrintError "[CreateServiceFile] The package ${PACKAGE_NAME} is not found under ${ROS2_WS_SRC_PATH} or ${ROS2_DEFAULT_SHARE_PATH} ."
        return 1
    fi

    # Is the package local or not
    local is_local=${pkg_islocal_dict["${PACKAGE_NAME}"]}

    # Run the custom script if exists
    if [ -f "${repo_path}/scripts/custom.sh" ]; then
        PrintInfo "[CreateServiceFile] Found custom script at ${repo_path}/scripts/custom.sh. Running..."
        # Pass the system.yaml path and repo path to the custom script
        sudo bash ${repo_path}/scripts/custom.sh "${system_path}" "${repo_path}" 2>&1 | PrintDebug
        if [ $? -ne 0 ]; then
            PrintError "[CreateServiceFile] The custom script is not correctly executed."
        else
            PrintSuccess "[CreateServiceFile] The custom script is executed successfully."
        fi
    fi

    # Get system.yaml parameters

    # Get params and launch file names
    local params_file=$(yaml ${system_path} "['launch']['params']")
    if [ -z "${params_file}" ]; then
        PrintError "[CreateServiceFile] The params file is not provided in the ${system_path}."
        return 1
    fi

    local launch_file=$(yaml ${system_path} "['launch']['launch']")
    if [ -z "${launch_file}" ]; then
        PrintError "[CreateServiceFile] The launch file is not provided in the ${system_path}."
        return 1
    fi

    local use_root=$(yaml ${system_path} "['launch']['use_root']")
    if [ -z "${use_root}" ]; then
        PrintWarning "[CreateServiceFile] The use_root is not provided in the ${system_path}. Default to False."
        use_root=False
    fi

    # The interface should be provided
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

    # Create runfile.sh under ${pkg_launcher_path} determined by the ${use_internet}
    if [ "${use_internet}" == "True" ]; then
        cp ${STARTUP_CONTENT_PATH}/scripts/run-internet-check.sh ${pkg_launcher_path}/runfile.sh
    else
        cp ${STARTUP_CONTENT_PATH}/scripts/run-network-check.sh ${pkg_launcher_path}/runfile.sh
    fi

    # Append ${repo_path}/scripts/source_env.sh to the runfile.sh if it exists
    if [ -f "${repo_path}/scripts/source_env.sh" ]; then
        PrintInfo "[CreateServiceFile] Found source_env.sh under ${repo_path}/scripts. Appending to the runfile.sh..."
        echo "" >> ${pkg_launcher_path}/runfile.sh
        cat ${repo_path}/scripts/source_env.sh >> ${pkg_launcher_path}/runfile.sh
        echo "" >> ${pkg_launcher_path}/runfile.sh
    fi

    # Finish the runfile.sh
    echo "export HOME=${HOME}" >> ${pkg_launcher_path}/runfile.sh

    if [ ${is_local} -eq 1 ]; then
        echo "source ${ROS2_WS_PATH}/install/setup.bash" >> ${pkg_launcher_path}/runfile.sh
    else
        echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ${pkg_launcher_path}/runfile.sh
    fi

    if [ ${use_config} -eq 0 ]; then
        echo "ros2 launch ${PACKAGE_NAME} ${launch_file} params_file:=${pkg_launcher_path}/${params_file}" >> ${pkg_launcher_path}/runfile.sh
    else
        echo "ros2 launch ${PACKAGE_NAME} ${launch_file} config_path:=${pkg_launcher_path}/${params_file}" >> ${pkg_launcher_path}/runfile.sh
    fi
    echo "sleep 5" >> ${pkg_launcher_path}/runfile.sh
    sudo chmod a+x ${pkg_launcher_path}/runfile.sh 2>&1 | PrintDebug
    PrintSuccess "[CreateServiceFile] The runfile.sh created at: ${pkg_launcher_path}/runfile.sh."

    local service_name=${STARTUP_NAME}_${PACKAGE_NAME}_${PACKAGE_ID}
    local service_file=${STARTUP_PKG_SERVICES_PATH}/${service_name}.service
    rm -rf ${service_file} && touch ${service_file}

    local user_id=$(id -un)
    local user_group=$(id -gn)

    echo "[Unit]" > ${service_file}
    echo "Description=${service_name}" >> ${service_file}
    echo "" >> ${service_file}
    echo "[Service]" >> ${service_file}

    if [ "${use_root}" == "False" ]; then # If user and group not specified, systemd runs the service as root.
        echo "User=${user_id}" >> ${service_file}
        echo "Group=${user_group}" >> ${service_file}
    fi

    echo "Type=simple" >> ${service_file}
    echo "ExecStart=${pkg_launcher_path}/runfile.sh ${interface}" >> ${service_file}
    echo "Restart=always" >> ${service_file}
    echo "" >> ${service_file}
    echo "[Install]" >> ${service_file}
    echo "WantedBy=multi-user.target" >> ${service_file}

    # Copy service file to /etc/systemd/system and enable the service
    sudo chmod 644 ${service_file} 2>&1 | PrintDebug
    sudo cp ${service_file} /etc/systemd/system 2>&1 | PrintDebug

    # Reload
    sudo systemctl daemon-reload 2>&1 | PrintDebug
    sudo systemctl enable ${service_name}.service 2>&1 | PrintDebug
    PrintSuccess "[CreateServiceFile] The service file created at: ${service_file}. The service is enabled."
    return 0
}

# Call by RemoveServiceFile
# RemoveServiceFile_ package_name package_id
RemoveServiceFile_ ()
{
    local service_name=${STARTUP_NAME}_$1_$2

    if sudo systemctl list-unit-files | grep -Foq "${service_name}.service"; then
        sudo systemctl stop ${service_name} 2>&1 | PrintDebug
        sudo systemctl disable ${service_name} 2>&1 | PrintDebug
        sudo rm /etc/systemd/system/${service_name}.service 2>&1 | PrintDebug
        PrintSuccess "[RemoveServiceFile_] The service ${service_name} is disabled and removed."
    fi

    # Remove the service file and runfile.sh
    rm -rf ${STARTUP_PKG_SERVICES_PATH}/${service_name}.service
    rm -rf ${STARTUP_PKG_SCRIPTS_PATH}/$1_$2/runfile.sh
    PrintInfo "[RemoveServiceFile_] The service ${service_name} is removed."
}

# The function will remove service file and delete service.
# The function requires the sudo permission.
RemoveServiceFile () {
    PrintDebug "[RemoveServiceFile] Removing the service file: ${PACKAGE_NAME}_${PACKAGE_ID} ..."

    if [[ "${PACKAGE_NAME}" == "NONE" ]] && [ ${ALL_FLAG} -eq 0 ]; then
        PrintError "[RemoveServiceFile] The package name is not provided."
        return 1
    fi

    if [[ "${PACKAGE_ID}" == "NONE" || ! ${PACKAGE_ID} =~ ${VALID_PACKAGE_ID_REGEX} ]] && [ ${ALL_FLAG} -eq 0 ]; then
        PrintError "[RemoveServiceFile] The package id is not provided or invalid."
        return 1
    fi

    if [ ${ALL_FLAG} -eq 0 ]; then
        RemoveServiceFile_ ${PACKAGE_NAME} ${PACKAGE_ID}
    else
        local service_paths=$(find ${STARTUP_PKG_SERVICES_PATH} -maxdepth 1 -type f -name "*.service")
        for service_path in ${service_paths}; do
            local pkg_launcher_name=$(basename ${service_path} | grep -Po "(?<=^${STARTUP_NAME}_)${VALID_PACKAGE_REGEX}_${VALID_PACKAGE_ID_REGEX}(?=.service$)")
            if [ -z "${pkg_launcher_name}" ]; then continue; fi

            local pkg_name=$(echo ${pkg_launcher_name} | grep -Po "^${VALID_PACKAGE_REGEX}(?=_${VALID_PACKAGE_ID_REGEX}$)")
            if [ -z "${pkg_name}" ]; then continue; fi

            local pkg_id=$(echo ${pkg_launcher_name} | grep -Po "(?<=_)${VALID_PACKAGE_ID_REGEX}$")
            if [ -z "${pkg_id}" ]; then continue; fi

            RemoveServiceFile_ ${pkg_name} ${pkg_id}
        done
    fi

    # Reload
    sudo systemctl daemon-reload 2>&1 | PrintDebug

    PrintSuccess "[RemoveServiceFile] The service files and runfile.sh are removed successfully."
    return 0
}

# The function will call the RemoveServiceFile() and remove the package directory.
# The function requires the sudo permission.
RemovePackageFile () {
    PrintDebug "[RemovePackageFile] Removing the package file: ${PACKAGE_NAME}_${PACKAGE_ID} ..."

    if [[ "${PACKAGE_NAME}" == "NONE" ]] && [ ${ALL_FLAG} -eq 0 ]; then
        PrintError "[RemovePackageFile] The package name is not provided."
        return 1
    fi

    if [[ "${PACKAGE_ID}" == "NONE" || ! ${PACKAGE_ID} =~ ${VALID_PACKAGE_ID_REGEX} ]] && [ ${PACKAGE_NO_LAUNCH} -eq 0 ] && [ ${ALL_FLAG} -eq 0 ] ; then
        PrintError "[RemovePackageFile] The package id is not provided or invalid."
        return 1
    fi

    if [ ${ALL_FLAG} -eq 0 ]; then
        if [ ${PACKAGE_NO_LAUNCH} -eq 0 ]; then
            RemoveServiceFile
        else
            PACKAGE_ID="nolaunch"
        fi
        rm -rf ${STARTUP_PKG_SCRIPTS_PATH}/${PACKAGE_NAME}_${PACKAGE_ID}
    else
        RemoveServiceFile
        rm -rf ${STARTUP_PKG_SCRIPTS_PATH}/*
    fi

    PrintSuccess "[RemovePackageFile] The package files are removed successfully."
    return 0
}

# The function will build ROS2 package accroding to the ${STARTUP_PKG_SCRIPTS_PATH}
# The function requires the sudo permission.
BuildPackage () {
    PrintDebug "[BuildPackage] Building the packages..."

    # Get the associative array of the ROS2 package name and path
    local -A pkg_path_dict
    local -A pkg_islocal_dict
    GetROS2PackageDict pkg_path_dict pkg_islocal_dict
    PrintDebug "$(declare -p pkg_path_dict)"
    PrintDebug "$(declare -p pkg_islocal_dict)"

    # Get required package list under ${STARTUP_PKG_SCRIPTS_PATH}
    local selected_pkg_set=() # The package selected to run install scripts.
    local build_pkg_set=() # The package to be built.

    # Install dependencies
    local apt_installed_list=$(apt list --installed 2>/dev/null)
    local pip_installed_list=$(${PYTHON3_PATH} -m pip list 2>/dev/null)

    local pkg_launcher_paths=$(find ${STARTUP_PKG_SCRIPTS_PATH} -maxdepth 1 -type d)
    for pkg_launcher_path in ${pkg_launcher_paths}; do
        # Get the package name from the directory name: <package_name>_<id>.
        local pkg_name=$(basename ${pkg_launcher_path} | grep -Po '^[a-z0-9_]+(?=_.*$)')
        if [ -z "${pkg_name}" ]; then continue; fi

        # Check if the package exists under ${ROS2_WS_SRC_PATH} or ${ROS2_DEFAULT_SHARE_PATH}
        if ! element_exists "${pkg_name}" "${!pkg_path_dict[@]}"; then
            PrintWarning "[BuildPackage][${pkg_name}] The package is not found under ${ROS2_WS_SRC_PATH} or ${ROS2_DEFAULT_SHARE_PATH} ."
            continue
        fi

        # Prevent duplicate package
        if element_exists "${pkg_name}" "${selected_pkg_set[@]}"; then continue; fi

        # Add package name to set
        selected_pkg_set+=("${pkg_name}")

        # Ignore non-local package
        if [ ${pkg_islocal_dict["${pkg_name}"]} -eq 1 ]; then
            build_pkg_set+=("${pkg_name}")
        fi

        # Dependence list file localtion (under <repo_path>/<package_name>/)
        local repo_path=${pkg_path_dict["${pkg_name}"]}
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
            sudo bash ${repo_path}/scripts/script_before_build.sh ${repo_path} 2>&1 | PrintDebug
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
        PrintWarning "[BuildPackage] Cleaning the build, install and log path..."
        sudo rm -rf ${build_path} ${inst_path} ${log_path}
    fi

    local pkg_str=$(echo "${build_pkg_set[@]}")
    PrintInfo "[BuildPackage] Building the package: [${pkg_str}]"
    if colcon --log-base ${log_path} build --cmake-args -DPython3_EXECUTABLE="${PYTHON3_PATH}" --build-base ${build_path} --install-base ${inst_path} --base-paths ${ROS2_WS_PATH} --packages-select ${pkg_str} --symlink-install 2>&1 | PrintDebug; then
        PrintSuccess "[BuildPackage] The package is built successfully."
    else
        PrintError "[BuildPackage] The package is not built successfully."
        return 1
    fi

    # Run after build script
    for pkg_name in ${selected_pkg_set[@]}; do
        local repo_path=${pkg_path_dict["${pkg_name}"]}
        if [ -f "${repo_path}/scripts/script_after_build.sh" ]; then
            PrintInfo "[BuildPackage][${pkg_name}] Found script_after_build.sh under ${repo_path}/scripts . Running..."
            # Pass the repo path to the script.
            sudo bash ${repo_path}/scripts/script_after_build.sh ${repo_path} 2>&1 | PrintDebug
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
RestoreRepos () {
    PrintDebug "[RestoreRepos] Restoring the repos to the current commit..."

    if ! CheckRepoList; then
        PrintError "[RestoreRepos] The repo list is not correctly deployed."
        return 1
    fi

    for repo_name in "${!REPO_URL_ARR[@]}"; do
        # Check if the repo is a directory and exist .git directory
        if [ ! -d "${ROS2_WS_SRC_PATH}/${repo_name}/.git" ]; then
            PrintWarning "[RestoreRepos] The repo ${repo_name} does not exist git control."
            continue
        fi
        pushd ${ROS2_WS_SRC_PATH}/${repo_name}
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git restore --staged . 2>&1 | PrintDebug
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git restore . 2>&1 | PrintDebug
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git clean -fd 2>&1 | PrintDebug
        popd
    done

    PrintSuccess "[RestoreRepos] The repos are restored to the current commit."
    return 0
}

# Function use git clone and pull to update the repos.
UpdateRepos () {
    PrintDebug "[UpdateRepos] Updating the repos..."

    if ! CheckRepoList; then
        PrintError "[UpdateRepos] The repo list is not correctly deployed."
        return 1
    fi

    for repo_name in "${!REPO_URL_ARR[@]}"; do
        local repo_url=${REPO_URL_ARR["${repo_name}"]}

        # Check if the repo is a directory and exist .git directory
        if [ ${CLEAN_FLAG} -eq 1 ] || [ ! -d "${ROS2_WS_SRC_PATH}/${repo_name}/.git" ]; then
            rm -rf ${ROS2_WS_SRC_PATH}/${repo_name}
            git clone ${repo_url} ${ROS2_WS_SRC_PATH}/${repo_name} 2>&1 | PrintDebug
            if [ $? -ne 0 ]; then
                PrintWarning "[UpdateRepos] The repo ${repo_name} is not correctly cloned."
            fi
            continue
        fi

        pushd ${ROS2_WS_SRC_PATH}/${repo_name}
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git add . 2>&1 | PrintDebug
        git --git-dir=${ROS2_WS_SRC_PATH}/${repo_name}/.git pull 2>&1 | PrintDebug
        popd
    done

    PrintSuccess "[UpdateRepos] The repos are updated successfully."
    return 0
}

# The function will update the packages.yaml from the ftp server.
UpdateRepoList () {
    local ftp_server_path=${FTP_SERVER_PATH}/${FTP_SERVER_REPO_VERSION}
    PrintDebug "[UpdateRepoList] Fetching the latest repo list from the ${FTP_SERVER_PATH} ..."

    if wget -q -O ${STARTUP_CONTENT_PATH}/packages.yaml ${ftp_server_path}/packages.yaml; then
        PrintSuccess "[UpdateRepoList] The repo list is fetched successfully."
        return 0
    fi

    PrintError "[UpdateRepoList] The repo list is not fetched successfully."
    return 1
}

# The function will list the package launcher and ROS2 packages.
List () {
    PrintDebug "[List] Listing the package launcher and ROS2 packages..."

    # ${LIST_MODE}: all, pkgs, scripts, services
    if [ "${LIST_MODE}" != "all" ] && [ "${LIST_MODE}" != "pkgs" ] && [ "${LIST_MODE}" != "scripts" ] && [ "${LIST_MODE}" != "services" ]; then
        PrintError "[List] The list mode is not valid."
        return 1
    fi

    # Set the silent mode
    SILENT_MODE=1

    # Get the associative array of the ROS2 package name and path
    local -A pkg_path_dict
    local -A pkg_islocal_dict
    GetROS2PackageDict pkg_path_dict pkg_islocal_dict
    PrintDebug "$(declare -p pkg_path_dict)"
    PrintDebug "$(declare -p pkg_islocal_dict)"

    # The two dicts describe the package launcher status. Package launcher: <package_name>_<id>
    local -A pkg_launcher_dict # { <package_name>_<id> : <pkg_name> }
    # Whether package launcher have service file.
    local -A pkg_launcher_status_dict # { <package_name>_<id> : {0|1} }

    local pkg_launcher_paths=$(find ${STARTUP_PKG_SCRIPTS_PATH} -maxdepth 1 -type d)
    for pkg_launcher_path in ${pkg_launcher_paths}; do
        # Get the package name from the directory name: <package_name>_<id>.
        local pkg_launcher_name=$(basename ${pkg_launcher_path})
        local pkg_name=$(echo ${pkg_launcher_name} | grep -Po '^[a-z0-9_]+(?=_.*$)')
        if [ -z "${pkg_name}" ]; then continue; fi

        # Check if the package exists under ${ROS2_WS_SRC_PATH} or ${ROS2_DEFAULT_SHARE_PATH}
        if ! element_exists "${pkg_name}" "${!pkg_path_dict[@]}"; then
            PrintWarning "[List][${pkg_name}] The package is not found under ${ROS2_WS_SRC_PATH} or ${ROS2_DEFAULT_SHARE_PATH} ."
            continue
        fi
        pkg_launcher_dict["${pkg_launcher_name}"]="${pkg_name}"

        # Check if the service file exists
        if [ -f "${STARTUP_PKG_SERVICES_PATH}/${STARTUP_NAME}_${pkg_launcher_name}.service" ]; then
            pkg_launcher_status_dict["${pkg_launcher_name}"]=1
        else
            pkg_launcher_status_dict["${pkg_launcher_name}"]=0
        fi
    done

    SILENT_MODE=0

    # Print list for 'scripts' and 'services' mode.
    if [ "${LIST_MODE}" == "scripts" ]; then
        if [ ${#pkg_launcher_status_dict[@]} -gt 0 ]; then
            PrintValue "$(echo ${!pkg_launcher_status_dict[@]})"
        fi
        return 0
    elif [ "${LIST_MODE}" == "services" ]; then
        local arr_=()
        for pkg_launcher_name in "${!pkg_launcher_status_dict[@]}"; do
            if [ ${pkg_launcher_status_dict["${pkg_launcher_name}"]} -eq 1 ]; then
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
    if ! CheckRepoList; then
        SILENT_MODE=0
        PrintError "[List] The repo list is not correctly deployed."
        return 1
    fi
    SILENT_MODE=0

    # Packages in ${ROS2_WS_SRC_PATH} or ${ROS2_DEFAULT_SHARE_PATH}
    local -A pkg_status_dict # { <pkg_name> : {0|1|2|3} }
    for pkg_name in "${!pkg_path_dict[@]}"; do
        pkg_status_dict["${pkg_name}"]=0
        if [ ${pkg_islocal_dict["${pkg_name}"]} -eq 1 ]; then # Package is local.
            pkg_status_dict["${pkg_name}"]=$(( pkg_status_dict["${pkg_name}"] + 1 ))
            if element_exists "${pkg_name}" "${!PKG_REPO_ARR[@]}"; then # Package in packages.yaml.
                pkg_status_dict["${pkg_name}"]=$(( pkg_status_dict["${pkg_name}"] + 2 ))
            fi
        fi
    done

    # Packages in packages.yaml
    for pkg_name in "${!PKG_REPO_ARR[@]}"; do
        if ! element_exists "${pkg_name}" "${!pkg_path_dict[@]}"; then # Package tracked but not fetched.
            pkg_status_dict["${pkg_name}"]=2
        fi
    done

    # Print list for 'all' and 'pkgs' mode.
    if [ "${LIST_MODE}" == "pkgs" ]; then
        for pkg_name in "${!pkg_status_dict[@]}"; do
            PrintValue "${pkg_name} ${pkg_status_dict["${pkg_name}"]}"
        done
    elif [ "${LIST_MODE}" == "all" ]; then
        local printed_pkg_name=()

        # First print the package launcher
        for pkg_launcher_name in "${!pkg_launcher_status_dict[@]}"; do
            local pkg_status=${pkg_launcher_status_dict["${pkg_launcher_name}"]}
            local pkg_name=${pkg_launcher_dict["${pkg_launcher_name}"]}
            local repo_status=${pkg_status_dict["${pkg_name}"]}
            if ! element_exists "${pkg_name}" "${printed_pkg_name[@]}"; then
                printed_pkg_name+=("${pkg_name}")
            fi
            PrintValue "${pkg_launcher_name} ${pkg_status} ${pkg_name} ${repo_status}"
        done

        # Then print rest of the packages
        for pkg_name in "${!pkg_status_dict[@]}"; do
            if element_exists "${pkg_name}" "${printed_pkg_name[@]}"; then
                continue
            fi
            PrintValue "- 0 ${pkg_name} ${pkg_status_dict["${pkg_name}"]}"
        done
    fi

    return 0
}


SetupModeCheck () {
    # 0: create, 1: create-service, 2: remove-service, 3: remove, 4: build, 5: restore-repos, 6: update-repos, 7: update-repo-list, 8: list
    PrintDebug "[SetupModeCheck] Setup mode: ${SETUP_MODE}"

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
    else
        PrintError "[SetupModeCheck] The setup mode is not valid: ${SETUP_MODE}."
        return 1
    fi
    return $?
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

# Check the setup mode
SetupModeCheck
if [ $? -ne 0 ]; then
    PrintError "[Script] The setup mode is not correctly executed."
    return 1
fi
