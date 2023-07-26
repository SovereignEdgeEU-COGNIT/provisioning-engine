#!/usr/bin/env bash

# -------------------------------------------------------------------------- #
# Copyright 2023, OpenNebula Project, OpenNebula Systems                     #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

install() {
	[ -d "$CONF_DIR" ] || sudo mkdir "$CONF_DIR"
	[ -L "$CONF_PATH" ] || sudo ln -s "share/etc/$CONF_FILE" "$CONF_DIR"
	[ -d "$install_dir" ] || mkdir "$install_dir"

	[ -L "$EXEC_FILE" ] || sudo ln -s "src/engine.rb" "$EXEC_FILE" && chmod +x "$EXEC_FILE"

	for file in $SRC; do
		dst="$install_dir/${file}"

		[ -L "$dst" ] || ln -s "$(realpath "src/${file}")" "${install_dir}/"
	done
}

clean() {
	echo "${CONF_DIR} and ${install_dir} will not be deleted as part of the cleanup process"

	[ -L $CONF_PATH ] && sudo rm $CONF_PATH
	[ -d "$install_dir" ] && rm "${install_dir}"/*
}

CONF_DIR="/etc/one"
CONF_FILE="provision_engine.conf"
CONF_PATH="${CONF_DIR}/${CONF_FILE}"
EXEC_FILE="/usr/bin/opengine"

SRC="log.rb configuration.rb API/rest.rb CloudClient/client.rb"
SRC="${SRC} Translator/data.rb Translator/function.rb Translator/runtime.rb"

action="${1:-"install"}"
install_dir="${2:-"/opt/ProvisionEngine"}"

if [ "$action" = "clean" ]; then
	clean
else
	install
fi
