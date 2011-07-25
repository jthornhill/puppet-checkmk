class checkmk{
    if $checkmkmoduledisabled {
    } else {
        include checkmk::agent
    }
}

class checkmk::agent {
    if $nagios_server {
    } else {
        $nagios_server = "10.1.1.1"
    }
    package { "check_mk-agent": 
        ensure => installed,
    }
    service { "xinetd":
        enable => true,
        ensure => running,
        subscribe => File["/etc/xinetd.d/check_mk"],
    }
    file { "/etc/xinetd.d/check_mk":
        ensure => file,
        content =>    template( "checkmk/check_mk.erb"),
        mode => 644,
        owner => root,
        group => root,
    }
    @@file { "/etc/check_mk/conf.d/puppet/$fqdn.mk":
        content => template( "checkmk/collection.mk.erb"),
        tag => "checkmk",
    }
}

class checkmk::server {
    $all_hosts = template('checkmk/nodelist.erb')
    exec { "checkmk_refresh":
        command => "/usr/bin/check_mk -I ; /usr/bin/check_mk -O",
        refreshonly => true,
    }
    File <<| tag == 'checkmk' |>> {
        notify => Exec["checkmk_refresh"],
    }
}

