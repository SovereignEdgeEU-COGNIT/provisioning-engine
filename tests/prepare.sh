#!/usr/bin/env bash

# How to use
# ./prepare.sh http://cognit-lab.sovereignedge.eu:2633/RPC2 http://cognit-lab.sovereignedge.eu:2474 0 1

install_gems() {
	gems=("rspec" "rack-test") # gems required for running the tests

	for gem in "${gems[@]}"; do
		gem list -i "$gem" >/dev/null 2>&1 || gem install "$gem"
	done
}

configure_engine() {
	oned=$1
	oneflow=$2
	nature=$3
	nature_s3=$4

	conf_path="/etc/provision-engine/engine.conf"

	  awk -v one_xmlrpc="$oned" \
      -v oneflow_server="$oneflow" \
      -v nature="$nature" \
      -v nature_s3="$nature_s3" \
      'BEGIN{OFS=FS}
      /:one_xmlrpc:/{ $2=" " one_xmlrpc " "; }
      /:oneflow_server:/{ $2=" " oneflow_server " "; }
      /:nature:/{ $2=" " nature " "; }
      /:nature-s3:/{ $2=" " nature_s3 " "; }
      {print}' "$conf_path" > /tmp/engine.conf && mv /tmp/engine.conf "$conf_path"
}

install_engine() {
	cd ..
	./install.sh
	cd - || exit
}

install_engine && configure_engine "$1" "$2" "$3" "$4" && install_gems

