#!/bin/bash

echo "Starting Industrial Shields PLC..."

export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/host/run/dbus/system_bus_socket

# rpiplc hw-config 
# ExecStartPre equivalent: Wait for /dev/ttySC* to exist
while [ ! -c /dev/ttySC* ]; do 
    sleep 1
done
sleep 1

echo "Starting after detecting ttySC0..."

# ExecStart equivalent: Run the hw-config command
/usr/local/bin/hw-config

sleep infinity
