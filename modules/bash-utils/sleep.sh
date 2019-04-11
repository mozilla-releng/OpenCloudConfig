#!/bin/bash

sleep_with_countdown() {
  remaining_seconds=$1
  message_prefix=$2
  message_suffix=$3
  while [ $remaining_seconds -gt 0 ]; do
    printf "\r\033[K${message_prefix}%.d seconds${message_suffix}" $((remaining_seconds--))
    sleep 1
  done
  echo
}