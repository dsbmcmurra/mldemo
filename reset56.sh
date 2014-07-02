#!/bin/bash
mld -action stop -datastore /opt/cariden/mldata/datastore;
sleep 1
embedded_web_server -action stop
sleep 5
rm -rf /opt/cariden/mldata/*
rm -rf /opt/cariden/archives/mldemo
rm -rf /opt/cariden/software/mld
rm -rf /opt/cariden/bin/nvsdemo/bin/state.txt
rm -rf /opt/cariden/etc/config/config.xml
archive_init -archive /opt/cariden/archives/mldemo -timeplot-summary-format /opt/cariden/etc/matelive/default_timeplot_summary_format.txt
source ~/.bashrc
mld -action install -size D -cpus 1 -mldata /opt/cariden/mldata

sleep 1
mate_cfg -application Live -action set -key DatesRelativeToLatestData -value True
embedded_web_server -action start

