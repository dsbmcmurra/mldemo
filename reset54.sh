#!/bin/bash
mld -action stop -datastore /opt/cariden/mldata/datastore;
sleep 1
embedded_web_server -action stop
sleep 5
rm -rf /opt/cariden/mldata/*
rm -rf /opt/cariden/archives/mldemo
rm -rf /opt/cariden/software/mld
rm -rf /opt/cariden/etc/config/config.xml
archive_init -archive /opt/cariden/archives/mldemo -timeplot-summary-format /opt/cariden/etc/matelive/default_timeplot_summary_format.txt
#cat /opt/cariden/bin/mldemo/archive.txt >> /opt/cariden/etc/matelive/default_timeplot_summary_format.txt
mld -action start -datastore /opt/cariden/mldata/datastore
sleep 1
embedded_web_server -action start
