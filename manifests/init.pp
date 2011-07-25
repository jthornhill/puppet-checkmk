## Puppet module to manage check_mk


# I like to have a convenience meta class that may be disabled with a variable; this part is completely optional
class checkmk{
    if $checkmkmoduledisabled {
    } else {
        include checkmk::agent
    }
}

# This section defines the agent
class checkmk::agent {
    # You probably want to configure nagios_server in your node classifier, but you may just add it here
    if $nagios_server {
    } else {
        $nagios_server = "10.1.1.1"
    }
    # Where the configs ultimately go; if you run a recent check_mk you can use a subdirectory of conf.d if you wish
    # as above this may be set in the classifier, but be sure all nodes running the agent have this in their scope
    if $mk_confdir {
    } else {
        $mk_confdir = "/etc/check_mk/conf.d"
    }
    # ensure that your clients understand how to install the client (e.g. add it to a repo or add a source 
    # ensure that your clients understand how to install the client (e.g. add it to a repo or add a source 
    # entry here
    package { "check_mk-agent": 
        ensure => installed,
    }
    # the client runs from xinetd, enable it and subscribe it to the check_mk config
    service { "xinetd":
        enable => true,
        ensure => running,
        subscribe => File["/etc/xinetd.d/check_mk"],
    }
    # template restricts check_mk access to the nagios_server from above
    file { "/etc/xinetd.d/check_mk":
        ensure => file,
        content =>    template( "checkmk/check_mk.erb"),
        mode => 644,
        owner => root,
        group => root,
    }
    # the exported resource; the template will create a valid snippet of python code that check_mk
    # will understand. 
    @@file { "$mk_confdir/$fqdn.mk":
        content => template( "checkmk/collection.mk.erb"),
        tag => "checkmk",
    }
}

class checkmk::server {
    # the exec statement will cause check_mk to re-scan when new nodes are added
    exec { "checkmk_refresh":
        command => "/usr/bin/check_mk -I ; /usr/bin/check_mk -O",
        refreshonly => true,
    }
    # collect the exported resource from the clients; each one will have a corresponding config file
    # placed on the check_mk server
    File <<| tag == 'checkmk' |>> {
        notify => Exec["checkmk_refresh"],
    }
}

