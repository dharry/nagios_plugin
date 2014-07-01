nagios_plugin
=============

nagios/icingaのプラグインです。
nagios_plugin.rb は snmpwalkで取得して監視します。
xe_nagios_plugin.rb は xenserverのcli(xeコマンド)で取得して監視します。
それだけ。

* Free and open-source software: BSD license

# Quick Start

xenserverのcliであるxeコマンドは、xenserverのisoの中にあるxe-cli-X.X.X.rpmを取り出してインストールしてください。
nagios_plugin.rbとxe_nagios_plugin.rbは、$NAGIOSHOME/libexecに放り込んでください。
使い方は、testディレクトリのコードを参考に。
