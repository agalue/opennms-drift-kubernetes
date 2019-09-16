#!/usr/bin/env bash

if sshpass -p admin ssh -o StrictHostKeyChecking=no -p 8301 admin@localhost health:check | grep --quiet "Everything is awesome"; then exit 0; else exit 1; fi
