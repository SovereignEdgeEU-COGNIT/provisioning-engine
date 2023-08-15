#!/usr/bin/env bash


install() {
	for gem_name in "${gems[@]}"; do
		is_gem_installed "$gem_name" >/dev/null 2>&1 || gem install "$gem_name"
	done

	[ -d "$CONF_DIR" ] || sudo mkdir "$CONF_DIR"
	[ -L "$CONF_PATH" ] || sudo ln -s "$(realpath "share/etc/$CONF_FILE")" "$CONF_DIR"
	[ -d "$install_dir" ] || sudo mkdir "$install_dir"

	[ -L "$EXEC_FILE" ] || sudo ln -s "${install_dir}/rest.rb" "$EXEC_FILE"

	for file in $SRC; do
		dst="$install_dir/${file}"

		[ -L "$dst" ] || ln -s "$(realpath "src/${file}")" "${install_dir}/"
	done
}

# TODO: Make thorough clean
clean() {
	echo "${CONF_DIR} and ${install_dir} will not be deleted as part of the cleanup process"

	[ -L $CONF_PATH ] && sudo rm $CONF_PATH
	[ -d "$install_dir" ] && rm "${install_dir}"/*

	# for gem_name in "${gems[@]}"; do
	# 	is_gem_installed "$gem_name" && gem uninstall "$gem_name"
	# done
}

is_gem_installed() {
  gem list -i "$1" >/dev/null 2>&1
}

CONF_DIR="/etc/provision-engine"
CONF_FILE="provision_engine.conf"
CONF_PATH="${CONF_DIR}/${CONF_FILE}"
EXEC_FILE="/usr/local/bin/provision-engine-server"

SRC="log.rb configuration.rb"
SRC="${SRC} API/rest.rb CloudClient/client.rb"
SRC="${SRC} Translator/data.rb Translator/function.rb Translator/runtime.rb"

gems=("opennebula" "sinatra" "logger")

action="${1:-"install"}"
install_dir="${2:-"/opt/provision-engine"}"

if [ "$action" = "clean" ]; then
	clean
else
	install
fi
