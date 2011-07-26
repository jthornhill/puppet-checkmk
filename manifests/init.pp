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
        $mk_confdir = "/etc/check_mk/conf.d/puppet"
    }
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
    # the exported file resource; the template will create a valid snippet of python code in a file named after the host
    @@file { "$mk_confdir/$fqdn.mk":
        content => template( "checkmk/collection.mk.erb"),
        notify => Exec["checkmk_inventory_$fqdn"],
        tag => "checkmk_conf",
    }
    # the exported exec resource; this will trigger a check_mk inventory of the specific node whenever its config changes
    @@exec { "checkmk_inventory_$fqdn":
        command => "/usr/bin/check_mk -I $fqdn",
        notify => Exec["checkmk_refresh"],
        refreshonly => true,
        tag => "checkmk_inventory",
    }
}

class checkmk::server {
    # ths exec statement will cause check_mk to regenerate the nagios config when new nodes are added
    exec { "checkmk_refresh":
        command => "/usr/bin/check_mk -O",
        refreshonly => true,
    }
    # collect the exported resource from the clients; each one will have a corresponding config file
    # placed on the check_mk server
    File <<| tag == 'checkmk_conf' |>> {
    }
    # in addition, each one will have a corresponding exec resource, used to re-inventory changes
    Exec <<| tag == 'checkmk_inventory' |>> {
    }
    # finally, we prune any not-managed-by-puppet files from the directory, and refresh nagios when we do so
    # NB: for this to work, your $mk_confdir must be totally managed by puppet; if it's not you should disable
    # this resource. Newer versions of check_mk support reading from subdirectories under conf.d, so you can dedicate
    # one specifically to the generated configs
    file { "$mk_confdir":
        ensure => directory,
        purge => true,
        notify => Exec["checkmk_refresh"],
    }
}

