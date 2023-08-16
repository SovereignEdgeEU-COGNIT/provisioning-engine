#!/usr/bin/env bash

one="172.20.0.8"
executor="one@supermicro9"

ssh -v -N -L 1338:$one:2633 $executor
ssh -v -N -L 1339:$one:2474 $executor
ssh -v -N -L 9869:$one:9869 $executor
