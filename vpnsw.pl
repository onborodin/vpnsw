#!@PERL@

#
# $Id$
#
# -*- mode: perl;-*-

#------------
#--- CRON ---
#------------

package Cron;

use strict;
use warnings;


sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub ping {
    my $self = shift;
    my $res = "Pong!";
    $res;
}

1;

#--------------
#--- DAEMON ---
#--------------

package Daemon;

use strict;
use warnings;
use POSIX qw(getpid setuid setgid geteuid getegid);
use Cwd qw(cwd getcwd chdir);
use Mojo::Util qw(dumper);

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub fork {
    my $self = shift;
    my $pid = fork;
    if ($pid > 0) {
        exit;
    }
    chdir("/");
    open(my $stdout, '>&', STDOUT); 
    open(my $stderr, '>&', STDERR);
    open(STDOUT, '>>', '/dev/null');
    open(STDERR, '>>', '/dev/null');
    getpid;
}

1;

package VPN;

use strict;
use warnings;
use Mojo::Util qw(dumper);
use File::Basename qw(basename dirname);
use POSIX;
use Config;

sub new {
    my ($class, $app) = @_;
    my $self = {
        app => $app,
    };
    bless $self, $class;
    return $self;
}

sub app {
    return shift->{app};
}

sub conf_list {
    my ($self, $confdir) = @_;
    return undef unless $confdir;

    opendir(my $dh, $confdir);
    my @list;
    while (my $name = readdir($dh)) {
        next unless ($name =~ m/^\w{1,64}.conf$/);
        next if -d $name;
        push @list, "$confdir/$name";
    }
    closedir $dh;
    return \@list;
}

sub conf_parse {
    my ($self, $filename) = @_;
    return undef unless $filename;
    return undef unless (-f $filename && -r $filename);

    open(my $fh, '<:encoding(UTF-8)', $filename) or return undef;
    my %list;
    while (my $row = <$fh>) {
        my $key;
        my $value;

        ($key, $value) = $row =~ /^(log)\s{1,20}([\/a-z0-9.]{1,64})/;
        $list{$key} = $value if $key;

        ($key, $value) = $row =~ /^(status)\s{1,20}([\/_A-Za-z0-9.]{1,64})/;
        $list{$key} = $value if $key;

        my $val2;
        ($key, $value, $val2) = $row =~ /^(server)\s{1,20}([\/0-9.]{1,64})\s{1,20}([\/0-9.]{1,64})/;
        $list{$key} = "$value/$val2" if $key;
    }
    return \%list;
}

sub stat_parse {
    my ($self, $filename) = @_;
    return undef unless $filename;
    return undef unless (-f $filename && -r $filename);

    open(my $fh, '<:encoding(UTF-8)', $filename) or return undef;
    my %hash;
    while (my $row = <$fh>) {
        my $key;
        my $value;
        #Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since
        #c_MSK__Moscow__Personal__Kalinina,176.193.136.206:49675,1731236,1985610,Wed Oct 25 10:30:54 2017 
        my ($cn, $ipaddr, $recv, $sent, $total, $date) = $row 
            =~ /([\w\-]{1,64}),([\/a-z0-9.]{1,64}):([0-9]{1,16}),([0-9]{1,16}),([0-9]{1,16}),([\w\: ]{1,20})/;
        $hash{$cn}{'ipaddr'} = $ipaddr if $cn;
        $hash{$cn}{'recv'} = $recv if $cn;
        $hash{$cn}{'sent'} = $sent if $cn;
        $hash{$cn}{'total'} = $total if $cn;
        $hash{$cn}{'date'} = $date if $cn;

        #Virtual Address,Common Name,Real Address,Last Ref
        #10.170.160.27,c_MSK__MSK__Personal__URS-Belousova,188.164.141.20:54440,Wed Oct 25 20:53:51 2017
        my ($local, $cn2, $ipaddr2, $some, $last) = $row 
            =~ /^([0-9.]{1,64}),([\w\-]{1,64}),([0-9.]{1,64}):([0-9]{1,16}),([\w\: ]{1,20})/;
        $hash{$cn2}{'local'} = $local if $local;
        $hash{$cn2}{'last'} = $last if $local;

        my ($net, $cn3, $ipaddr3, $some2, $last2) = $row 
            =~ /^([0-9.]{1,64}\/[0-9]{2}),([\w\-]{1,64}),([0-9.]{1,64}):([0-9]{1,16}),([\w\: ]{1,20})/;
        push @{$hash{$cn3}{'net'}}, $net if $net;

        my ($wclient, $cn4, $ipaddr4, $some3, $last4) = $row 
            =~ /^([0-9.]{1,64}C),([\w\-]{1,64}),([0-9.]{1,64}):([0-9]{1,16}),([\w\: ]{1,20})/;
        $wclient =~ s/C// if $wclient;
        push @{$hash{$cn4}{'wclient'}}, $wclient if $wclient;

    }
    return \%hash;
}

sub conf_basename {
    my ($self, $filename) = @_;
    return undef unless $filename;
    $filename = basename ($filename, ".conf");
    return $filename if $filename;
    return undef;
}

sub system_comm {
    my ($self, $comm) = @_;
    return undef unless $comm;
    open HR, "$comm |" or return undef;
    my $out; 
    while (my $str = <HR>) { 
        $out .= $str;
    };
    return $out;
}


sub service_status {
    my ($self, $name) = @_;
    return undef unless $name;
    my $osname = $Config{osname};
    if ($osname =~ /bsd/) {
        my $out = $self->system_comm("sudo service openvpn status $name 2>&1") || '';
        return 'up' if $out =~ m/is running/;
        return 'down' if $out =~ m/is not running/;
    } else {
        my $out = $self->system_comm("sudo systemctl status openvpn\@$name 2>&1") || '';
        return 'up' if $out =~ m/Active: active/;
        return 'down' if $out =~ m/Active: inactive/;
    }
    return undef;
}


sub service_start {
    my ($self, $name) = @_;
    return undef unless $name;
    my $osname = $Config{osname};
    my $out;
    if ($osname =~ /bsd/) {
        $out = $self->system_comm("sudo service openvpn start $name 2>&1") || '';
    } else {
        $out = $self->system_comm("sudo systemctl start openvpn\@$name 2>&1") || '';
    }
    $self->app->log->info("service_start: Start service $name with result $out");
    my $s = $self->service_status($name) || '';
    return 1 if $s eq 'up';
    undef;
}

sub service_stop {
    my ($self, $name) = @_;
    return undef unless $name;
    my $osname = $Config{osname};
    my $out;
    if ($osname =~ /bsd/) {
        $out = $self->system_comm("sudo service openvpn stop $name 2>&1") || '';
    } else {
        $out = $self->system_comm("sudo systemctl stop openvpn\@$name 2>&1") || '';
    }
    $self->app->log->info("service_start: Stop service $name with result $out");
    my $s = $self->service_status($name) || '';
    return 1 if $s eq 'down';
    return undef;
}


sub pack_ipaddr {
    my ($self, $addr) = @_;
    return undef unless $addr;

    my ($ipaddr, $mask) = split "[/]", $addr;
    return undef unless $ipaddr;
    return undef unless $mask;

    my %mask2cidr = (
              '255.255.255.255'   => '32',
              '255.255.255.254'   => '31',
              '255.255.255.252'   => '30',
              '255.255.255.248'   => '29',
              '255.255.255.240'   => '28',
              '255.255.255.224'   => '27',
              '255.255.255.192'   => '26',
              '255.255.255.128'   => '25',
              '255.255.255.0'     => '24',
              '255.255.254.0'     => '23',
              '255.255.252.0'     => '22',
              '255.255.248.0'     => '21',
              '255.255.240.0'     => '20',
              '255.255.224.0'     => '19',
              '255.255.192.0'     => '18',
              '255.255.128.0'     => '17',
              '255.255.0.0'       => '16',
              '255.254.0.0'       => '15',
              '255.252.0.0'       => '14',
              '255.248.0.0'       => '13',
              '255.240.0.0'       => '12',
              '255.224.0.0'       => '11',
              '255.192.0.0'       => '10',
              '255.128.0.0'       => '9',
              '255.0.0.0'         => '8',
              '254.0.0.0'         => '7',
              '252.0.0.0'         => '6',
              '248.0.0.0'         => '5',
              '240.0.0.0'         => '4',
              '224.0.0.0'         => '3',
              '192.0.0.0'         => '2',
              '128.0.0.0'         => '1',
    );
    my $bitc = $mask2cidr{$mask} || undef;
    return undef unless $bitc;
    return "$ipaddr/$bitc";
}

1;

package VPNsw::Controller;

use utf8;
use strict;
use warnings;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(md5_sum dumper quote encode);
use Mojo::JSON qw(encode_json decode_json);
use Apache::Htpasswd;
use File::Basename qw(fileparse);

sub vpn_list {
    my $self = shift;
    $self->render(template => 'vpn-list');
}

sub vpn_info {
    my $self = shift;
    $self->render(template => 'vpn-info');
}

sub hello {
    my $self = shift;
    $self->render(template => 'hello');
}

sub index {
    my $self = shift;
    $self->redirect_to("/vpn/list");
}

sub vpn_all {
    my $self = shift;
    $self->render(template => 'vpn-all');
}

#----------------
#--- AJAX API ---
#----------------

sub vpn_start {
    my $self = shift;
    my $service = $self->req->param('service');
    return $self->render(json => {} ) unless $service;
    $self->app->vpn->service_start($service);
    my $status = $self->app->vpn->service_status($service);
    $self->render(json => {service => $service, status => $status } );
}

sub vpn_stop {
    my $self = shift;
    my $service = $self->req->param('service');
    return $self->render(json => {} ) unless $service;
    $self->app->vpn->service_stop($service);
    my $status = $self->app->vpn->service_status($service);
    $self->render(json => {service => $service, status => $status } );
}


#--------------------
#--- SESSION CONT ---
#--------------------

sub pwfile {
    my ($self, $pwdfile) = @_;
    return $self->app->config('pwdfile') unless $pwdfile;
    $self->app->config(pwfile => $pwdfile);
}

sub ucheck {
    my ($self, $username, $password) = @_;
    return undef unless $password;
    return undef unless $username;
    my $pwdfile = $self->pwfile or return undef;
    my $res = undef;
    eval {
        my $ht = Apache::Htpasswd->new({ passwdFile => $pwdfile, ReadOnly => 1 });
        $res = $ht->htCheckPassword($username, $password);
    };
    $self->app->log->info("ucheck: $@") if $@;
    $res;
}

sub login {
    my $self = shift;
    return $self->redirect_to('/') if $self->session('username');

    my $username = $self->req->param('username') || undef;
    my $password = $self->req->param('password') || undef;

    return $self->render(template => 'login') unless $username and $password;

    if ($self->ucheck($username, $password)) {
        $self->session(username => $username);
        return $self->redirect_to('/');
    }
    $self->render(template => 'login');
}

sub logout {
    my $self = shift;
    $self->session(expires => 1);
    $self->redirect_to('/');
}


1;

#-----------
#--- APP ---
#-----------

package VPNsw;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';

sub startup {
    my $self = shift;
}

1;

#------------
#--- MAIN ---
#------------

use strict;
use warnings;

use POSIX qw(setuid setgid tzset tzname strftime);
use Mojo::Server::Prefork;
use Mojo::IOLoop::Subprocess;
use Mojo::Util qw(md5_sum b64_decode getopt dumper);
use Sys::Hostname qw(hostname);
use File::Basename qw(basename dirname);
use Apache::Htpasswd;
use Cwd qw(getcwd abs_path);
use EV;

my $appname = 'vpnsw';

#--------------
#--- GETOPT ---
#--------------

getopt
    'h|help' => \my $help,
    'c|config=s' => \my $conffile,
    'f|nofork' => \my $nofork,
    'u|user=s' => \my $user,
    'g|group=s' => \my $group;


if ($help) {
    print qq(
Usage: app [OPTIONS]

Options
    -h | --help           This help
    -c | --config=path    Path to config file
    -u | --user=user      System owner of process
    -g | --group=group    System group 
    -f | --nofork         Dont fork process

The options override options from configuration file
    )."\n";
    exit 0;
}


my $server = Mojo::Server::Prefork->new;
my $app = $server->build_app('VPNsw');
$app = $app->controller_class('VPNsw::Controller');

$app->secrets(['6d578e43ba88260e0375a1a35fd7954b']);
$app->static->paths(['@APP_LIBDIR@/public']);
$app->renderer->paths(['@APP_LIBDIR@/templs']);

$app->config(conffile => $conffile || '@APP_CONFDIR@/vpnsw.conf');
$app->config(pwdfile => '@APP_CONFDIR@/vpnsw.pw');
$app->config(logfile => '@APP_LOGDIR@/vpnsw.log');
$app->config(loglevel => 'info');
$app->config(pidfile => '@APP_RUNDIR@/vpnsw.pid');
$app->config(crtfile => '@APP_CONFDIR@/vpnsw.crt');
$app->config(keyfile => '@APP_CONFDIR@/vpnsw.key');

$app->config(listenaddr4 => '0.0.0.0');
#$app->config(listenaddr6 => '[::]');
$app->config(listenport => '1007');

$app->config(user => $user || '@APP_USER@');
$app->config(group => $group || '@APP_GROUP@');

$app->config(confdir => "/etc/openvpn");

if (-r $app->config('conffile')) {
    $app->log->debug("Load configuration from ".$app->config('conffile'));
    $app->plugin('JSONConfig', { file => $app->config('conffile') });
}

#---------------
#--- HELPERS ---
#---------------
$app->helper(
    vpn => sub {
        state $vpn = VPN->new($app); 
});

$app->helper(
    cron => sub {
        my $cron = Cron->new;
        $cron;
});

$app->helper('reply.not_found' => sub {
        my $c = shift; 
        return $c->redirect_to('/login') unless $c->session('username'); 
        $c->render(template => 'not_found.production');
});


#--------------
#--- ROUTES ---
#--------------

my $r = $app->routes;

$r->add_condition(
    auth => sub {
        my ($route, $c) = @_;
        $c->session('username');
    }
);

$r->any('/login')->to('controller#login');
$r->any('/logout')->to('controller#logout');

$r->any('/')->over('auth')->to('controller#index' );
$r->any('/hello')->over('auth')->to('controller#hello');

$r->any('/vpn/list')->over('auth')->to('controller#vpn_list');
$r->any('/vpn/info')->over('auth')->to('controller#vpn_info');
$r->any('/vpn/all')->over('auth')->to('controller#vpn_all');

$r->any('/j/vpn/start')->over('auth')->to('controller#vpn_start');
$r->any('/j/vpn/stop')->over('auth')->to('controller#vpn_stop');
$r->any('/j/vpn/status')->over('auth')->to('controller#vpn_status');
$r->any('/j/vpn/list')->over('auth')->to('controller#vpn_status');

#----------------
#--- LISTENER ---
#----------------

my $tls = '?';
$tls .= 'cert='.$app->config('crtfile');
$tls .= '&key='.$app->config('keyfile');

my $listen4;
if ($app->config('listenaddr4')) {
    $listen4 = "https://";
    $listen4 .= $app->config('listenaddr4').':'.$app->config('listenport');
    $listen4 .= $tls;
}

my $listen6;
if ($app->config('listenaddr6')) {
    $listen6 = "https://";
    $listen6 .= $app->config('listenaddr6').':'.$app->config('listenport');
    $listen6 .= $tls;
}

my @listen;
push @listen, $listen4 if $listen4;
push @listen, $listen6 if $listen6;

$server->listen(\@listen);
$server->heartbeat_interval(3);
$server->heartbeat_timeout(60);


#-----------------
#--- DOEMINIZE ---
#-----------------

unless ($nofork) {
    my $d = Daemon->new;
    my $user = $app->config('user');
    my $group = $app->config('group');
    $d->fork;
    $app->log(Mojo::Log->new( 
                path => $app->config('logfile'),
                level => $app->config('loglevel')
    ));
}

$server->pid_file($app->config('pidfile'));

#---------------
#--- WEB LOG ---
#---------------

$app->hook(before_dispatch => sub {
        my $c = shift;

        my $remote_address = $c->tx->remote_address;
        my $method = $c->req->method;

        my $base = $c->req->url->base->to_string;
        my $path = $c->req->url->path->to_string;
        my $loglevel = $c->app->log->level;
        my $url = $c->req->url->to_abs->to_string;

        unless ($loglevel eq 'debug') {
            #$c->app->log->info("$remote_address $method $base$path");
            $c->app->log->info("$remote_address $method $url");
        }
        if ($loglevel eq 'debug') {
            $c->app->log->debug("$remote_address $method $url");
        }
});

#----------------------
#--- SIGNAL HANDLER ---
#----------------------

local $SIG{HUP} = sub {
    $app->log->info('Catch HUP signal'); 
    $app->log(Mojo::Log->new(
                    path => $app->config('logfile'),
                    level => $app->config('loglevel')
    ));
};


#my $sub = Mojo::IOLoop::Subprocess->new;
#$sub->run(
#    sub {
#        my $subproc = shift;
#        my $loop = Mojo::IOLoop->singleton;
#        my $id = $loop->recurring(
#            1200 => sub {
#                my $res = $app->cron->ping;
#                $app->log->info($res);
#            }
#        );
#        $loop->start unless $loop->is_running;
#        1;
#    },
#    sub {
#        my ($subprocess, $err, @results) = @_;
#        $app->log->info('Exit subprocess');
#        1;
#    }
#);
#
#my $pid = $sub->pid;
#$app->log->info("Subrocess $pid start ");
#
#$server->on(
#    finish => sub {
#        my ($prefork, $graceful) = @_;
#        $app->log->info("Subrocess $pid stop");
#        kill('INT', $pid);
#    }
#);

$server->run;

#EOF
