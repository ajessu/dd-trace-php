#!/bin/bash --login

return 0;

EXTENSION_BASE_DIR=/opt/datadog-php
EXTENSION_DIR=${EXTENSION_BASE_DIR}/extensions
EXTENSION_CFG_DIR=${EXTENSION_BASE_DIR}/etc
EXTENSION_LOGS_DIR=${EXTENSION_BASE_DIR}/log
EXTENSION_SRC_DIR=${EXTENSION_BASE_DIR}/dd-trace-sources
EXTENSION_AUTO_INSTRUMENTATION_FILE=${EXTENSION_SRC_DIR}/bridge/dd_wrap_autoloader.php
INI_FILE_NAME='ddtrace.ini'
CUSTOM_INI_FILE_NAME='ddtrace-custom.ini'

PATH="${PATH}:/usr/local/bin"

if [[ -z "$DD_TRACE_PHP_BIN" ]]; then
    DD_TRACE_PHP_BIN=$(command -v php)
fi

function println(){
    echo -e '###' "$@"
}

function append_configuration_to_file() {
    tee -a "$@" <<EOF
; Autogenerated by the Datadog post-install.sh script

${INI_FILE_CONTENTS}

; end of autogenerated part
EOF
}

function create_configuration_file() {
    tee "$@" <<EOF
; ***** DO NOT EDIT THIS FILE *****
; To overwrite the INI settings for this extension, edit
; the INI file in this directory called "${CUSTOM_INI_FILE_NAME}"

${INI_FILE_CONTENTS}
EOF
}

function generate_configuration_files() {
    INI_FILE_PATH="${EXTENSION_CFG_DIR}/$INI_FILE_NAME"
    CUSTOM_INI_FILE_PATH="${EXTENSION_CFG_DIR}/$CUSTOM_INI_FILE_NAME"

    println "Creating ${INI_FILE_NAME}"
    println "\n"

    create_configuration_file "${INI_FILE_PATH}"

    println "${INI_FILE_NAME} created"
    println

    if [[ ! -f $CUSTOM_INI_FILE_PATH ]]; then
        touch "${CUSTOM_INI_FILE_PATH}"
        println "Created empty ${CUSTOM_INI_FILE_PATH}"
        println
    fi
}

function link_ini_file() {
    test -f "${2}" && rm "${2}"
    ln -s "${1}" "${2}"
}

function install_conf_d_files() {
    generate_configuration_files

    println "Linking ${INI_FILE_NAME} for supported SAPI's"
    println "\n"

    # Detect installed SAPI's
    SAPI_DIR=${PHP_CFG_DIR%/*/conf.d}/
    SAPI_CONFIG_DIRS=()
    if [[ "$PHP_CFG_DIR" != "$SAPI_DIR" ]]; then
        # Detect CLI
        if [[ -d "${SAPI_DIR}cli/conf.d" ]]; then
            SAPI_CONFIG_DIRS+=("${SAPI_DIR}cli/conf.d")
        fi
        # Detect FPM
        if [[ -d "${SAPI_DIR}fpm/conf.d" ]]; then
            SAPI_CONFIG_DIRS+=("${SAPI_DIR}fpm/conf.d")
        fi
        # Detect Apache
        if [[ -d "${SAPI_DIR}apache2/conf.d" ]]; then
            SAPI_CONFIG_DIRS+=("${SAPI_DIR}apache2/conf.d")
        fi
    fi

    if [ ${#SAPI_CONFIG_DIRS[@]} -eq 0 ]; then
        SAPI_CONFIG_DIRS+=("$PHP_CFG_DIR")
    fi

    for SAPI_CFG_DIR in "${SAPI_CONFIG_DIRS[@]}"
    do
        println "Found SAPI config directory: ${SAPI_CFG_DIR}"

        PHP_DDTRACE_INI="${SAPI_CFG_DIR}/98-${INI_FILE_NAME}"
        println "Linking ${INI_FILE_NAME} to ${PHP_DDTRACE_INI}"
        link_ini_file "${INI_FILE_PATH}" "${PHP_DDTRACE_INI}"

        CUSTOM_PHP_DDTRACE_INI="${SAPI_CFG_DIR}/99-${CUSTOM_INI_FILE_NAME}"
        println "Linking ${CUSTOM_INI_FILE_NAME} to ${CUSTOM_PHP_DDTRACE_INI}"
        link_ini_file "${CUSTOM_INI_FILE_PATH}" "${CUSTOM_PHP_DDTRACE_INI}"
        println
    done
}

function fail_print_and_exit() {
    println 'Failed enabling ddtrace extension'
    println
    println "The extension has been installed but couldn't be enabled"
    println "Try adding the extension manually to your PHP - php.ini - configuration file"
    println "e.g. by adding following line: "
    println
    println "    extension=${EXTENSION_FILE_PATH}"
    println
    println "Note that your PHP API version must match the extension's API version"
    println "PHP API version can be found using following command"
    println
    println "    $DD_TRACE_PHP_BIN -i | grep 'PHP API'"
    println

    exit 0 # exit - but do not fail the installation
}

function verify_installation() {
    $DD_TRACE_PHP_BIN -m | grep ddtrace && \
        println "Extension enabled successfully" || \
        fail_print_and_exit
}

mkdir -p $EXTENSION_DIR
mkdir -p $EXTENSION_CFG_DIR
mkdir -p $EXTENSION_LOGS_DIR

println 'Installing Datadog PHP tracing extension (ddtrace)'
println
println "Logging $DD_TRACE_PHP_BIN -i to a file"
println

$DD_TRACE_PHP_BIN -i > "$EXTENSION_LOGS_DIR/php-info.log"

PHP_VERSION=$($DD_TRACE_PHP_BIN -i | awk '/^PHP[ \t]+API[ \t]+=>/ { print $NF }')
PHP_CFG_DIR=$($DD_TRACE_PHP_BIN -i | grep 'Scan this dir for additional .ini files =>' | sed -e 's/Scan this dir for additional .ini files =>//g' | head -n 1 | awk '{print $1}')

PHP_THREAD_SAFETY=$($DD_TRACE_PHP_BIN -i | grep 'Thread Safety' | awk '{print $NF}' | grep -i enabled)

VERSION_SUFFIX=""
if [[ -n $PHP_THREAD_SAFETY ]]; then
    VERSION_SUFFIX="-zts"
fi

OS_SPECIFIER=""
if [ -f "/etc/os-release" ] && [ grep -q 'NAME="Alpine Luinux"' "/etc/os-release" ]; then
    OS_SPECIFIER="-alpine"
fi

EXTENSION_NAME="ddtrace-${PHP_VERSION}${OS_SPECIFIER}${VERSION_SUFFIX}.so"
EXTENSION_FILE_PATH="${EXTENSION_DIR}/${EXTENSION_NAME}"
INI_FILE_CONTENTS=$(cat <<EOF
[datadog]
extension=${EXTENSION_FILE_PATH}
ddtrace.request_init_hook=${EXTENSION_AUTO_INSTRUMENTATION_FILE}
EOF
)

if [[ ! -e $PHP_CFG_DIR ]]; then
    println
    println 'conf.d folder not found falling back to appending extension config to main "php.ini"'
    PHP_CFG_FILE_PATH=$($DD_TRACE_PHP_BIN -i | grep 'Configuration File (php.ini) Path =>' | sed -e 's/Configuration File (php.ini) Path =>//g' | head -n 1 | awk '{print $1}')
    PHP_CFG_FILE="${PHP_CFG_FILE_PATH}/php.ini"
    if [[ ! -e $PHP_CFG_FILE_PATH ]]; then
        fail_print_and_exit
    fi

    if grep -q "${EXTENSION_FILE_PATH}" "${PHP_CFG_FILE}"; then
        println
        println '    extension configuration already exists skipping'
    else
        append_configuration_to_file "${PHP_CFG_FILE}"
    fi
else
    install_conf_d_files
fi

verify_installation
