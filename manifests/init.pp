## Puppet module to manage check_mk

# I like to have a convenience meta class that may be disabled with a variable; this part is completely optional
class checkmk{
    if $::checkmkmoduledisabled {
    } else {
        include checkmk::agent
    }
}

# This section defines the agent
class checkmk::agent {
    # You probably want to configure nagios_server in your node classifier, but you may just add it here
    if $::nagios_server {
        $nagios_server = "$::nagios_server"
    } else {
        $nagios_server = "10.1.1.1"
    }
    # Where the configs ultimately go; if you run a recent check_mk you can use a subdirectory of conf.d if you wish
    # as above this may be set in the classifier, but be sure all nodes running the agent have this in their scope
    if $::mk_confdir {
        $mk_confdir = $::mk_confdir
    } else {
        $mk_confdir = "/etc/check_mk/conf.d/puppet"
    }
    # it is possible that $::fqdn may not exist; fall back on $::hostname if it does not
    if $::fqdn {
        $mkhostname = $::fqdn
    } else {
        $checkmk_no_resolve = true
        $mkhostname = $::hostname
    }
    # in cases where name resolution fails, we can hard-code the IP address by setting
    # the $check_mk_override_ip variable for the node
    # if we cannot resolve and no address is specified, we use facter's best guess for IP address
    if $::checkmk_override_ip {
        $override_ip = $::checkmk_override_ip
    } else {
        $override_ip = $::ipaddress
    }
    # ensure that your clients understand how to install the agent (e.g. add it to a repo or add a source 
    # entry to this) for this to work
    package { "check_mk-agent": 
        ensure => installed,
    }
    # the agent runs from xinetd, enable it and subscribe it to the check_mk config
    service { "xinetd":
        enable => true,
        ensure => running,
        subscribe => File["/etc/xinetd.d/check_mk"],
    }
    # the template restricts check_mk access to the nagios_server from above
    file { "/etc/xinetd.d/check_mk":
        ensure => file,
        content =>    template( "checkmk/check_mk.erb"),
        mode => 644,
        owner => root,
        group => root,
    }
    # the exported file resource; the template will create a valid snippet of python code in a file named after the host
    @@file { "$mk_confdir/$mkhostname.mk":
        content => template( "checkmk/collection.mk.erb"),
        notify => Exec["checkmk_inventory_$mkhostname"],
        tag => "checkmk_conf_$nagios_server",
    }
    # the exported exec resource; this will trigger a check_mk inventory of the specific node whenever its config changes
    @@exec { "checkmk_inventory_$mkhostname":
        command => "/usr/bin/check_mk -I $mkhostname",
        notify => Exec["checkmk_refresh"],
        refreshonly => true,
        tag => "checkmk_inventory_$nagios_server",
    }
}

class checkmk::server {
    if $::mk_confdir {
        $mk_confdir = $::mk_confdir
    } else {
        $mk_confdir = "/etc/check_mk/conf.d/puppet"
    }

    # ths exec statement will cause check_mk to regenerate the nagios config when new nodes are added
    exec { "checkmk_refresh":
        command => "/usr/bin/check_mk -O",
        refreshonly => true,
    }

    # this check uses the $nagios_server variable to determine where resources should be collected
    # i.e.: $nagios_server must be the same on a nagios server and on nagios clients

    # if you have more than one nagios server managing the same sets of clients you can set this to 
    # a string used by all of them, and assign the IPs or FQDNs of the servers directly in the xinetd
    # template instead of using the $nagios_server variable to set the ACL there
    
    # collect the exported resource from the clients; each one will have a corresponding config file
    # placed on the check_mk server

    File <<| tag == "checkmk_conf_$nagios_server" |>> {
    }

    # in addition, each one will have a corresponding exec resource, used to re-inventory changes
    Exec <<| tag == "checkmk_inventory_$nagios_server" |>> {
    }

    # finally, we prune any not-managed-by-puppet files from the directory, and refresh nagios when we do so
    # NB: for this to work, your $mk_confdir must be totally managed by puppet; if it's not you should disable
    # this resource. Newer versions of check_mk support reading from subdirectories under conf.d, so you can dedicate
    # one specifically to the generated configs
    file { "$mk_confdir":
        ensure => directory,
        purge => true,
        recurse => true,
        notify => Exec["checkmk_refresh"],
    }
}

