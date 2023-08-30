#!/usr/bin/env bash

install() {
	for gem in "${gems[@]}"; do
		is_gem_installed "$gem" || gem install "$gem"
	done

	[ -d "$CONF_DIR" ] || sudo mkdir "$CONF_DIR"
	[ -d "$INSTALL_DIR" ] || mkdir "$INSTALL_DIR"

	if [[ $setup_mode == "copy" ]]; then
		[ -f "$CONF_PATH" ] || sudo cp "$(realpath "share/etc/$CONF_FILE")" "$CONF_DIR"
	elif [[ $setup_mode == "symlink" ]]; then
		[ -L "$CONF_PATH" ] || [ -f "$CONF_PATH" ] || sudo ln -s "$(realpath "share/etc/$CONF_FILE")" "$CONF_DIR"
	fi

	for file in $modules; do
		dst="$INSTALL_DIR/${file}"

		if [[ $setup_mode == "copy" ]]; then
			[ -L "$dst" ] || cp "$(realpath "src/server/${file}")" "${INSTALL_DIR}/"
		elif [[ $setup_mode == "symlink" ]]; then
			[ -L "$dst" ] || ln -s "$(realpath "src/server/${file}")" "${INSTALL_DIR}/"
		fi
	done

	# server.rb is installed as the executable
	[ -L "$EXEC_FILE" ] || sudo ln -s "${INSTALL_DIR}/server.rb" "$EXEC_FILE"
}

postinstall() {
	[ -L "$EXEC_FILE" ] || sudo ln -s "${INSTALL_DIR}/server.rb" "$EXEC_FILE"
	echo "provision engine installed at ${INSTALL_DIR}"
	echo "run engine with ${EXEC_FILE} start/stop"
}

clean() {
	if [[ $setup_mode == "purge" ]]; then
		[ -d $CONF_DIR ] && sudo rm -r $CONF_DIR

		for gem in "${gems[@]}"; do
			remove_orphan_gem "$gem"
		done

		[ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
		[ -f "$EXEC_FILE" ] && sudo rm $EXEC_FILE
	else
		echo "${CONF_DIR} will not be deleted as part of the cleanup process"
		echo "The ruby gems: $(printf "%s " "${gems[@]}") are required by the provision engine"

		[ -f "$CONF_PATH" ] && sudo rm $CONF_PATH
		[ -L "$EXEC_FILE" ] && sudo rm $EXEC_FILE
	fi

}

is_gem_installed() {
	gem list -i "$1" >/dev/null 2>&1
}

remove_orphan_gem() {
	gem uninstall -a --abort-on-dependent "$1" >/dev/null 2>&1
}

CONF_DIR="/etc/provision-engine"
CONF_FILE="engine.conf"
CONF_PATH="${CONF_DIR}/${CONF_FILE}"
EXEC_FILE="/usr/local/bin/provision-engine-server"
INSTALL_DIR="/opt/provision-engine" # install location is hardcoded

modules="client.rb configuration.rb log.rb server.rb runtime.rb"
gems=("opennebula" "sinatra" "logger" "json-schema") # check requires on server.rb

action="${1:-"install"}"
setup_mode="${2:-"symlink"}" # TODO: change to copy once is production ready

if [ "$action" = "clean" ]; then
	clean
else
	install && postinstall
fi
