#!/bin/bash

bundle check || bundle install

rm -f tmp/pids/server.pid

rails db:migrate

rails s -b '0.0.0.0'
