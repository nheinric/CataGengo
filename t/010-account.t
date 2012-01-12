#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/./lib";
use lib "$FindBin::Bin/../lib";

use CataGengo::Test::Util::Client;

use Getopt::Long;
use Test::More;
use DateTime;

use Data::Dumper;

BEGIN {
    use_ok 'CataGengo';
    use_ok 'CataGengo::View::Web';
    use_ok 'WebService::MyGengo::Base';
    use_ok 'WebService::MyGengo::Account';
}

my $LIVE    = $ENV{CATAGENGO_TEST_LIVE} || 0;
GetOptions(
    'live:i'      => \$LIVE
    );
$LIVE and $ENV{CATAGENGO_TEST_LIVE} = $LIVE;

use Test::WWW::Mechanize::Catalyst;
my $mech = Test::WWW::Mechanize::Catalyst->new(
    catalyst_app => 'CataGengo'
    );
$mech->add_header( 'Accept-Language' => 'en' );

# Need to do this before making Catalyst calls
my $client = client();

my @tests = qw/accounts_page/;
run_tests();
done_testing();

################################################################################
sub run_tests {
    foreach ( @tests ) {
        no strict 'refs';
        eval { &$_() };
        $@ and fail("Error in test $_: ".Dumper($@));
    }
}

sub accounts_page {
    # Grab the Account direct from the API for comparison
    my $failures = 0;
    my $acct = $client->get_account();
    
    $mech->get_ok( '/mygengo/account', "Got account page" );
    $mech->title_is( 'Account', "Title OK" );
    
    $mech->text_contains( $acct->user_since->strftime('%F %H:%M:%S %Z')
        , "Found user-since datetime" )
        or $failures++;
    $mech->text_contains( $acct->credits_spent." Credits"
        , "Found credits spent" )
        or $failures++;
    
    $mech->text_contains( $acct->credits." Credits"
        , "Found credits" )
        or $failures++;

    my $tab = $mech->find_link( id => 'account-view-tab' );
    if ( !$tab ) {
        diag "Links: ".Dumper($mech->links());
        fail( "account-view-tab not found." );
    }
    else {
        is( $tab->attrs->{class}, 'selected', "Tab is selected" );
    }

    $failures and diag "Content: ".Dumper($mech->content)."\n";
}

