#!/usr/bin/env bash

install() {
	for gem in "${gems[@]}"; do
		is_gem_installed "$gem" || sudo gem install "$gem"
	done

	[ -d "$CONF_DIR" ] || sudo mkdir "$CONF_DIR"
	[ -d "$INSTALL_DIR" ] || mkdir "$INSTALL_DIR"

	src_conf="$(realpath "share/etc/$CONF_FILE")"
	src_exec="$(realpath src/server/cli/provision-engine-server)"

	if [[ $setup_mode == "copy" ]]; then
		[ -f "$CONF_PATH" ] || sudo cp "$src_conf" "$CONF_PATH"
		[ -L "$EXEC_PATH" ] || sudo cp "$src_exec" "$EXEC_PATH"

		for file in $modules; do
			[ -L "$INSTALL_DIR/${file}" ] || cp "$(realpath "src/server/${file}")" "${INSTALL_DIR}"
		done
	elif [[ $setup_mode == "symlink" ]]; then
		[ -L "$CONF_PATH" ] || [ -f "$CONF_PATH" ] || sudo ln -s "$src_conf" "$CONF_PATH"
		[ -L "$EXEC_PATH" ] || sudo ln -s "$src_exec" "$EXEC_PATH"

		for file in $modules; do
			[ -L "$INSTALL_DIR/${file}" ] || ln -s "$(realpath "src/server/${file}")" "${INSTALL_DIR}"
		done
	fi
}

postinstall() {
	echo "provision engine installed at ${INSTALL_DIR}"
	echo "run engine with ${EXEC_PATH} start/stop"
}

clean() {
	if [[ $setup_mode == "purge" ]]; then
		[ -d $CONF_DIR ] && sudo rm -r $CONF_DIR

		for gem in "${gems[@]}"; do
			remove_orphan_gem "$gem"
		done
	else
		echo "${CONF_DIR} will not be deleted as part of the cleanup process"
		echo "The ruby gems: $(printf "%s " "${gems[@]}") are required by the provision engine"
	fi

	[ -f "$EXEC_PATH" ] && sudo rm $EXEC_PATH
	[ -L "$EXEC_PATH" ] && sudo rm $EXEC_PATH
	[ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
}

is_gem_installed() {
	sudo gem list -i "$1" >/dev/null 2>&1
}

remove_orphan_gem() {
	sudo gem uninstall -a --abort-on-dependent "$1" >/dev/null 2>&1
}

CONF_DIR="/etc/provision-engine"
CONF_FILE="engine.conf"
CONF_PATH="${CONF_DIR}/${CONF_FILE}"
EXEC_FILE="provision-engine-server"
EXEC_PATH="/usr/local/bin/${EXEC_FILE}"
INSTALL_DIR="/opt/provision-engine" # install location is hardcoded

modules="client.rb configuration.rb log.rb server.rb runtime.rb"
gems=("opennebula" "sinatra" "logger" "json-schema") # check requires on server.rb

action="${1:-"install"}"
setup_mode="${2:-"symlink"}"

if [ "$action" = "clean" ]; then
	clean
else
	install && postinstall
fi
