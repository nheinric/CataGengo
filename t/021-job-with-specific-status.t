#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/./lib";
use lib "$FindBin::Bin/../lib";

=head1 DESCRIPTION

I split these into a separate class because they require Jobs that are in
a particular status to run.

This is most easily accomplished by injecting Jobs into the mock
LWP::UserAgent, as seen in the L<SYNOPSIS: Mock>.

However, if you want to run these against the sanbox, the test will detect
the $ENV{CATAGENGO_TEST_LIVE} flag, create some dummy Jobs in your sandbox
and ask you to modify them through the sandbox website before continuing,
as in L<SYNOPSIS: Live>.

See L<CataGengo::Test::Util::Client> for more details on how the mock
setup works.

=head1 SYNOPSIS: Mock

    use CataGengo::Test::Util::Job;
    use CataGengo::Test::Util::Client;

    $ENV{CATAGENGO_TEST_LIVE} = 0;
    my $client  = client();

    # Plant a Job that's in reviewable status
    my $job              = dummy_job_hash();
    $job->{job_id}       = 8675309;
    $job->{status}       = 'reviewable';
    $job->{captcha_url}  = 'http://hamburglar.com/captcha.png';

    $client->_user_agent->add_job( $job );

    # Because the mock is a singleton, this works:
    $mech->get_ok('/mygengo/job/'.$job->id, "Got Job details page");
    $mech->title_is( 'Job Details - '.$job->id, "Job page title has Job ID" );

    # In case you feel like cleaning up after yourself
    $client->_user_agent->delete_jobs( $job->id );

=head1 SYNOPSIS: Live

    bash> perl -I t/lib -I lib t/021-job-with-specific-status.t --live 1
    ...
    [info] CataGengo powered by Catalyst 5.90007
    ok 1 - use CataGengo;
    ok 2 - use CataGengo::Model::MyGengo;
    ok 3 - use CataGengo::View::Web;
    Submitting test Jobs to the sandbox...
    Submitting test Jobs to the sandbox...
    ...
    4 dummy Jobs have been created in your sandbox.
    Set 3 of them to 'reviewable' status.
    Set 1 of them to 'pending' status.
    Please run the test again with the "--live 2" flag to execute the real tests
    bash>

=cut
use CataGengo::Test::Util::Client;
use CataGengo::Test::Util::Job;

use WebService::MyGengo::Job;
use WebService::MyGengo::Comment;

use Getopt::Long;
use Test::WWW::Mechanize::Catalyst;
use Test::More;

use Data::Dumper;

BEGIN {
    use_ok 'CataGengo'; # The Catalyst app
    use_ok 'CataGengo::Model::MyGengo'; # todo move Model to Catalyst namespace
    use_ok 'CataGengo::View::Web';
}

# CLI options
my $DEBUG   = undef;
my $FILTER  = undef;
my $LIVE    = $ENV{CATAGENGO_TEST_LIVE} || 0;
GetOptions(
    'debug'         => \$DEBUG
    , 'filter=s'    => \$FILTER
    , 'live:i'      => \$LIVE
    );
$LIVE and $ENV{CATAGENGO_TEST_LIVE} = $LIVE;

my $tests = [
                '_setup'    # Not really a test, but sets up test Jobs in live mode
                , 'can_successfully_plant_custom_job'
                , 'canceling_job_that_isnt_available_throws_exception'
                , 'request_revision_for_reviewable_job'
                , 'request_revision_for_non_reviewable_job_throws_exception'
                , 'approve_reviewable_job'
                , 'approve_non_reviewable_job_throws_exception'
                , 'reject_reviewable_job'
                , 'reject_non_reviewable_job_throws_exception'
                , 'revisions_display_for_approved_job'
                , 'revisions_do_not_display_for_unapproved_job'
            ];

run_tests();
teardown_jobs();
done_testing();

################################################################################
sub run_tests {
    my $client = client();
    my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'CataGengo');

    foreach ( @$tests ) {
        next if $FILTER && $_ !~ /.*$FILTER.*/;
        $DEBUG and diag "##### Start test: $_";
        no strict 'refs';
        eval { &$_( $client, $mech ) };
        $@ and fail("Error in test $_: ".Dumper($@));
        $DEBUG and diag "##### End   test: $_";
    }
}

sub _setup {
    if ( $LIVE == 1 ) {
        diag "Submitting test Jobs to the sandbox...";
        create_dummy_job() for ( 0 .. 4 );
        diag "
5 dummy Jobs have been created in your sandbox.
Set 3 of them to 'reviewable' status.
Set 1 of them to 'pending' status.
Set 1 of them to 'approved' status.
Please run the test again with the '--live 2' flag to execute the real tests
";
        done_testing();
        exit 0;
    }
    elsif ( $LIVE == 0 ) {
        my $client = client();
    
        my $struct              = dummy_job_hash();
        $struct->{status}       = 'pending';
        $client->_user_agent->add_job( $struct );

        $struct->{status}       = 'approved';
        $client->_user_agent->add_job( $struct );
    
        $struct->{status}       = 'reviewable';
        $client->_user_agent->add_job( $struct )
            for ( 0 .. 2 );
    }
}

sub can_successfully_plant_custom_job {
    my ( $client, $mech ) = ( @_ );

    SKIP: {
    skip "Test only valid when \$ENV{CATAGENGO_TEST_LIVE} == 0", 2
        unless $ENV{CATAGENGO_TEST_LIVE} == 0;

    # Plant a Job that's in reviewable status
    my $struct              = dummy_job_hash();
    $struct->{job_id}       = 8675309;
    $struct->{status}       = 'reviewable';
    $struct->{captcha_url}  = 'http://hamburglar.com/captcha.png';

    my $job = $client->_user_agent->add_job( $struct );

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job details page" );
    $mech->text_contains( 'Job: '.$job->id.' - '.ucfirst($job->status)
        , "Job header correct" )
        or diag "Content: ".$mech->content;

    $client->_user_agent->delete_jobs( $job->id );
    }
}

sub canceling_job_that_isnt_available_throws_exception {
    my ( $client, $mech ) = ( @_ );

    # Get a Job in pending state
    my $job = $client->search_jobs( 'pending' )->[0];
    !$job and die "Couldn't find a 'pending' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    # Attempt to cancel the Job, capturing the error screen
    $mech->{catalyst_debug} = 1;
    my $res = $mech->submit_form( form_id => 'cancel-job-form' );
    $mech->{catalyst_debug} = 0;

    ok( $res->is_error, "Response was an error" );
    $mech->text_contains("Error cancelling Job.", "Error found" ) ;

    $job = $client->get_job( $job->id );
    ok( $job, "Job still exists" );
    is( $job->status, 'pending', "Job is still pending" );
}

sub request_revision_for_reviewable_job {
    my ( $client, $mech ) = ( @_ );

    # Get a Job in reviewable state
    my $job = $client->search_jobs( 'reviewable' )->[0];
    !$job and die "Couldn't find a 'reviewable' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    # Request a revision with all available options
    $mech->submit_form_ok({
        form_id => 'status-update-form'
        , fields => {
            action => 'revise'
            , 'revise-comment' => "More cowbell, please."
            }
        });

    $mech->title_is( "Job Details - ".$job->id, "Redirected to Job details" );
    $mech->text_contains( 'Job: '.$job->id.' - Revising', "Job header correct" )
        or diag "Content: ".$mech->content;
    $mech->text_contains( 'More cowbell, please.' )
        or diag "Content: ".$mech->content;
}

sub request_revision_for_non_reviewable_job_throws_exception {
    my ( $client, $mech ) = ( @_ );

    # Get a Job in pending state
    my $job = $client->search_jobs( 'pending' )->[0];
    !$job and die "Couldn't find a 'pending' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    # Submit the request, capturing the error screen
    $mech->{catalyst_debug} = 1;
    $mech->post('/mygengo/job_actions/'.$job->id.'/put', {
        action => 'revise', 'revise-comment' => "More cowbell, please."
        } );
    $mech->{catalyst_debug} = 0;

    ok( $mech->res->is_error, "Response was an error" );
    $mech->text_contains("Error revise-ing Job.", "Error found" ) ;
}

sub approve_reviewable_job {
    my ( $client, $mech ) = ( @_ );

    # Get a Job in reviewable state
    my $job = $client->search_jobs( 'reviewable' )->[0];
    !$job and die "Couldn't find a 'reviewable' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    # Approve with all available options
    my $com1 = 'Good job, you should work for the UN or something.';
    my $com2 = 'This guy is the squizz.';
    $mech->submit_form_ok({
        form_id => 'status-update-form'
        , fields => {
            action => 'approve'
            , 'approve-rating' => 5
            , 'approve-for_translator' => $com1
            , 'approve-for_mygengo' => $com2
            , 'approve-public' => 1
            }
        });

    $mech->title_is( "Job Details - ".$job->id, "Redirected to Job details" );
    $mech->text_contains( 'Job: '.$job->id.' - Approved', "Job header correct" )
        or diag "Content: ".$mech->content;
    $mech->text_contains( 'Simulated translation', "body_tgt correct" )
        or diag "Content: ".$mech->content;
    $mech->text_lacks( $com1, "for_translator comment not added" )
        or diag "Content: ".$mech->content;
    $mech->text_lacks( $com2, "for_mygengo comment not added" )
        or diag "Content: ".$mech->content;
}

sub approve_non_reviewable_job_throws_exception {
    my ( $client, $mech ) = ( @_ );

    # Get a Job in pending state
    my $job = $client->search_jobs( 'pending' )->[0];
    !$job and die "Couldn't find a 'pending' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    # Submit the request, capturing the error screen
    my $com1 = 'Good job, you should work for the UN or something.';
    my $com2 = 'This guy is the squizz.';
    $mech->{catalyst_debug} = 1;
    $mech->post( '/mygengo/job_actions/'.$job->id.'/put', {
        action => 'approve'
        , 'approve-rating' => 5
        , 'approve-for_translator' => $com1
        , 'approve-for_mygengo' => $com2
        , 'approve-public' => 1
        } );
    $mech->{catalyst_debug} = 0;

    ok( $mech->res->is_error, "Response was an error" );
    $mech->text_contains("Error approve-ing Job.", "Error found" ) ;
}

sub reject_reviewable_job {
    my ( $client, $mech ) = ( @_ );

    SKIP: {
    skip "I don't know of a way to test the reject functionality with the"
        . " sandbox because I can't read the capctha image. Therefore, this"
        . " test will only run under \$ENV{CATAGENGO_TEST_LIVE} == 0"
        , 4, unless $ENV{CATAGENGO_TEST_LIVE} == 0;

    # Get a Job in reviewable state
    my $job = $client->search_jobs( 'reviewable' )->[0];
    !$job and die "Couldn't find a 'reviewable' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    # Reject with all available options
    my $com1 = 'If you want something done right...';
    $mech->submit_form_ok({
        form_id => 'status-update-form'
        , fields => {
            action => 'reject'
            , 'reject-reason' => 'incomplete'
            , 'reject-comment' => $com1
            , 'reject-captcha' => "1234"
            , 'reject-follow_up' => 'requeue'
            }
        });

    $mech->title_is( "Job Details - ".$job->id, "Redirected to Job details" );
    $mech->text_contains( 'Job: '.$job->id.' - Rejected', "Job header correct" )
        or diag "Content: ".$mech->content;

    }
}

sub reject_non_reviewable_job_throws_exception {
    my ( $client, $mech ) = ( @_ );

    # Get a Job in pending state
    my $job = $client->search_jobs( 'pending' )->[0];
    !$job and die "Couldn't find a 'pending' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    # Submit the request, capturing the error screen
    my $com1 = 'If you want something done right...';
    $mech->{catalyst_debug} = 1;
    $mech->post( '/mygengo/job_actions/'.$job->id.'/put', {
            action => 'reject'
            , 'reject-reason' => 'incomplete'
            , 'reject-comment' => $com1
            , 'reject-captcha' => "1234"
            , 'reject-follow_up' => 'requeue'
            } );
    $mech->{catalyst_debug} = 0;

    ok( $mech->res->is_error, "Response was an error" );
    $mech->text_contains("Error reject-ing Job.", "Error found" ) ;
}

sub revisions_display_for_approved_job {
    my ( $client, $mech ) = ( @_ );

    # Get a Job in pending state
    my $job = $client->search_jobs( 'approved' )->[0];
    !$job and die "Couldn't find a 'approved' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    $mech->content_like( qr{<label.*Revisions}, "Found Revisions header" );
}

sub revisions_do_not_display_for_unapproved_job {
    my ( $client, $mech ) = ( @_ );

    # Get a Job in pending state
    my $job = $client->search_jobs( 'pending' )->[0];
    !$job and die "Couldn't find a 'pending' Job to test!";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    $mech->content_unlike( qr{<label.*Revisions}, "No Revisions header" );
}
