#!/bin/bash
# Carrier detecting
reg_err='^(169\.254)'
reg_ipv4='([0-9]{1,3}\.){3}[0-9]{1,3}'
printf "%s" "Carrier connecting..."
while ! ip addr show dev $1 | grep -P 'inet(?!\d+)' | grep -Po $reg_ipv4 &> /dev/null
do
    printf "%c" "."
done
printf "\t%s\n" "Carrier detected."

# Network detecting
printf "%s" "Network connecting..."
while ip addr show dev $1 | grep -P 'inet(?!\d+)' | grep -Po $reg_ipv4 | grep -P $reg_err &> /dev/null
do
    printf "%c" "."
done
printf "\t%s\n" "Network detected."

# Internet connecting
printf "%s" "Internet connecting..."
while ! ping -w 1 -c 1 -n 168.95.1.1 &> /dev/null
do
    printf "%c" "."
done
printf "\n%s\n" "Internet connected."

# Process here
