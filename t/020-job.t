#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/./lib";
use lib "$FindBin::Bin/../lib";

use Getopt::Long;
use Test::More;

BEGIN {
    use_ok 'CataGengo'; # The Catalyst app
    use_ok 'CataGengo::Model::MyGengo'; # todo move Model to Catalyst namespace
    use_ok 'CataGengo::View::Web';
    use_ok 'WebService::MyGengo::Job';
    use_ok 'WebService::MyGengo::Comment';
}

use CataGengo::Test::Util::Client;
use CataGengo::Test::Util::Job;

use Data::Dumper;

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

use Test::WWW::Mechanize::Catalyst;
my $mech = Test::WWW::Mechanize::Catalyst->new(
    catalyst_app => 'CataGengo'
    );
$mech->add_header( 'Accept-Language' => 'en' );

my $client = client();

my $tests = [
    'view_all_jobs'
    , 'view_job_details'
    , 'post_job_comment'
    , 'posting_empty_comment_throws_exception'
    , 'post_new_job_page_ok'
    , 'post_new_job'
    , 'new_job_appears_in_jobs_list'
    , 'deleted_job_disappears_from_jobs_list'
    , 'submitting_jew_job_with_empty_body_src_throws_exception'
    , 'submitting_jew_job_with_no_language_setting_throws_exception'
    , 'can_estimate_job_cost'
    , 'fields_are_preserved_after_estimating_cost_for_new_job'
    ];

run_tests();
teardown_jobs();
done_testing();

################################################################################
sub run_tests {
    foreach ( @$tests ) {
        next if $FILTER && $_ !~ /.*$FILTER.*/;
        $DEBUG and diag "##### Start test: $_";
        no strict 'refs';
        eval { &$_() };
        $@ and fail("Error in test $_: ".Dumper($@));
        $DEBUG and diag "##### End   test: $_";
    }
}

sub view_all_jobs {
    # Make sure we have at least 1 job that will show up
    my $job1 = create_dummy_job();
    my $job2 = create_dummy_job();

    foreach my $job ( ($job1, $job2) ) {
        my $dt = $job->ctime->strftime('%F %H:%M:%S %Z');
    
        unless ( $mech->get_ok( '/mygengo/jobs', "Got jobs page" ) ) {
            diag "Content: ".$mech->content;
            return 0;
        }
    
        $mech->title_is( 'All Jobs', "Title OK" );
    
        my $tab = $mech->find_link( id => 'jobs-tab' );
        ok( $tab, "Found Jobs tab" )
            and is( $tab->attrs->{class}, 'selected', "Tab is selected" );
    
        foreach ( qw/job_id lc_src lc_tgt tier status auto_approve
                    body_src custom_data/ )
        {
            my $val = $job->$_ || '';
            $val = substr($val, 0, 47)."..." if $_ =~ /body_src/;
            $mech->content_like( qr{>\s*$val\s*</}, "Has $_" );
        }
    
        $mech->content_like( qr{>\s*$dt\s*</}, "Has ctime" )
            or diag "Content: ".$mech->content;
    }
}

sub view_job_details {
    my $job = create_dummy_job();
    my $dt = $job->ctime->strftime('%F %H:%M:%S %Z');
    my $eta = DateTime::Format::Duration->new(
        pattern => '%dD, %HH, %MM'
        , normalize => 1
        );
    $eta = $eta->format_duration( $job->eta );

    if ( !$mech->get_ok( '/mygengo/job/'.$job->id, "Got job page" ) ) {
        diag "Content: ".$mech->content;
        return 0;
    }

    $mech->title_is( 'Job Details - '.$job->id, "Title OK" )
        or diag "Content: ".$mech->content;

    my $tab = $mech->find_link( id => 'jobs-tab' );
    ok( $tab, "Found Jobs tab" )
        and is( $tab->attrs->{class}, 'selected', "Tab is selected" );

    # Check visible attributes
    foreach ( qw/lc_src lc_tgt unit_count tier credits status
                 body_src custom_data/ )
    {
        my $val = $job->$_ || '';
        $mech->content_like( qr{>\s*$val\s*</}, "Has $_" );
    }

    $mech->content_like( qr{>\s*$dt\s*</}, "Has ctime" )
        or diag "Content: ".$mech->content;
    $mech->content_like( qr{>\s*$eta\s*</}, "Has eta" )
        or diag "Content: ".$mech->content;

    # Check for comments list
    foreach ( $job->comments ) {
        my $regex = '<tr.*'.$_->ctime.'.*'.$_->author.'.*'.$_->body.'.*</tr>';
        $mech->content_like( qr{$regex}, "Has comment row" );
    }
}

sub post_job_comment {
    my $job = create_dummy_job();
    my $comment_count = $job->comment_count;
    my $body = "Frontend comment".rand();

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    $mech->submit_form_ok({
        form_id => 'comment-form'
        , fields => { comment_body => $body }
        }, "Submitted comment-form" );

    $mech->title_is( 'Job Details - '.$job->id, "Redirected to Job details" )
        or diag "Content: ".$mech->content;

    # Check the job directly from the API, just in case
    $job = $client->get_job( $job->id, 1 );
    cmp_ok( $job->comment_count, '==', $comment_count+1
        , "1 new comment was added");
    my $comment = $job->get_comment( $job->comment_count-1 );
    is( $comment->body, $body, "Comment added as latest comment" );
}

sub posting_empty_comment_throws_exception {
    my $job = create_dummy_job();
    my $comment_count = $job->comment_count;
    my $body = "";

    $mech->get_ok( '/mygengo/job/'.$job->id, "Got Job page" );

    # We want to capture the error screen
    $mech->{catalyst_debug} = 1;
    my $res = $mech->submit_form(
        form_id => 'comment-form'
        , fields => { comment_body => $body }
        );
    $mech->{catalyst_debug} = 0;

    ok( $res->is_error, "Response was an error" );

    $mech->text_contains("Empty comment body.", "Empty body error in content" );
    
    TODO: {
    local $TODO = "For some reason I -always- get 'authentication didn\'t"
        . "pass' exceptions from the sandbox right at this point, despite the"
        . " fact that previous identical requests pass. Throttling?";
    # Check the job directly from the API, just in case
    $job = $client->get_job( $job->id, 1 );
    ok( $job, "Got Job from API" );
    $job and cmp_ok( $job->comment_count, '==', $comment_count
        , "Comment count unchanged");
    }
}

sub post_new_job_page_ok {
    $mech->get_ok('/mygengo/job', "Got new job page");
    
    # Basic page checks
    $mech->title_is( 'New Job', 'Title OK' )
        or diag "Content: ".$mech->content;

    my $tab = $mech->find_link( id => 'new_job-tab' );
        is( $tab->attrs->{class}, 'selected', "Tab is selected" );

    # See if the language pairs are in the page
    my $pairs = $client->get_service_language_pairs();

    foreach ( @$pairs ) {
        my $pair = $_->lc_src.'::'.$_->lc_tgt.'::'.$_->tier;
        $mech->content_contains( $pair, "Found pair $pair" );
    }
}

sub post_new_job {
    my $lc_src = 'en';
    my $lc_tgt = 'de';
    my $tier = 'standard';
    my $fields = {
            'language_pair'     => $lc_src.'::'.$lc_tgt.'::'.$tier
            , 'body_src'        => "This is emphatically NOT a pen.".rand()
            , 'comment'         => "This is my homework, please xlate carefully."
            , 'custom_data'     => "'Big Book o' Deutsch, volume 1, chapter 77"
            , 'force'           => 1
            , 'use_preferred'   => 1
            , 'auto_approve'    => 1
            };

    $mech->get('/mygengo/job');
    $mech->submit_form_ok({
        fields => $fields
        }, "Submitted new Job form" );

    my $title = $mech->title;
    like( $title, qr{Job Details - \d+}, "Title ok" )
        or diag "Content: ".Dumper($mech->content);

    (my $job_id = $mech->title) =~ s/.*- //;
    my $job = $client->get_job( $job_id, 1 );

    # Check for comments list
    foreach ( $job->comments ) {
        my $regex = '<tr.*'.$_->ctime.'.*'.$_->author.'.*'.$_->body.'.*</tr>';
        $mech->content_like( qr{$regex}, "Has comment row" );
    }

    # Fields we submitted
    is( $job->lc_src, $lc_src, "lc_src ok" );
    is( $job->lc_tgt, $lc_tgt, "lc_tgt ok" );
    is( $job->tier, $tier, "tier ok" );
    is( $job->body_src, $fields->{body_src}, "body_src ok" );
    is( $job->comment->body, $fields->{comment}, "comment ok" );
    is( $job->comment_count, 1, "only 1 comment" );
    is( $job->custom_data, $fields->{custom_data}, "custom_data ok" );
    is( $job->force, $fields->{force}, "force ok" );
    is( $job->use_preferred, $fields->{use_preferred}, "use_preferred ok" );
    is( $job->auto_approve, $fields->{auto_approve}, "auto_approve ok" );

    # Fields the API fills in.
    # todo Do we even need to check these?
    is( $job->status, 'available', "Job status OK" );
    ok( $job->unit_count, "Job has unit count" );
    ok( $job->credits, "Job has credits" );
    isa_ok( $job->ctime, "DateTime", "Job has a ctime" );
    # todo ETA could be 0 :p
    isa_ok( $job->eta, "DateTime::Duration", "Job has an ETA" );

    client()->delete_job( $job );
}

sub new_job_appears_in_jobs_list {
    my $fields = dummy_job_hash_frontend();

    $mech->get('/mygengo/job');
    $mech->submit_form_ok({
        fields => $fields
        }, "Submitted new Job form" );

    $mech->get_ok( '/mygengo/jobs', "Got jobs page" )
        or diag "Content: ".$mech->content;

    my $src_short = substr($fields->{body_src}, 0, 47) . "...";

    $mech->content_like( qr{>\s*$src_short\s*</}, "Has body_src" )
        or diag "Content: ".$mech->content;
}

sub deleted_job_disappears_from_jobs_list {
    my $fields = dummy_job_hash_frontend();

    $mech->get('/mygengo/job');
    $mech->submit_form_ok({
        fields => $fields
        }, "Submitted new Job form" );

    (my $job_id = $mech->title) =~ s/.*- //;
    my $job = $client->get_job( $job_id );
    my $src_short = substr($job->body_src, 0, 47) . "...";

    $mech->get('/mygengo/jobs');
    $mech->content_like( qr{>\s*$src_short\s*</}, "Has body_src in jobs page" )
        or diag "Content: ".$mech->content;

    # Cancel the Job
    $mech->get('/mygengo/job/'.$job->id);
    $mech->submit_form_ok({
        form_id => 'cancel-job-form'
        }, "Submitted cancel Job form" );

    $mech->title_is( 'All Jobs', "Redirected to all jobs page" );
    $mech->content_unlike( qr{>\s*$src_short\s*</}, "Job is not in list" )
        or diag "Content: ".$mech->content;
}

sub submitting_jew_job_with_empty_body_src_throws_exception {
    my $fields = dummy_job_hash_frontend();
    $fields->{body_src} = undef;

    $mech->get('/mygengo/job');

    # We want to capture the error screen
    $mech->{catalyst_debug} = 1;
    $mech->submit_form( fields => $fields );
    $mech->{catalyst_debug} = 0;

    ok( $mech->res->is_error, "Response was an error" );

    $mech->text_contains(
        "Cannot submit_job without a body_src, lc_src, lc_tgt and tier"
        , "Empty body error in content"
        );
}

sub submitting_jew_job_with_no_language_setting_throws_exception {
    my $fields = dummy_job_hash_frontend();
    $fields->{language_pair} = undef;

    $mech->get('/mygengo/job');

    # We want to capture the error screen
    $mech->{catalyst_debug} = 1;
    $mech->submit_form( fields => $fields );
    $mech->{catalyst_debug} = 0;

    ok( $mech->res->is_error, "Response was an error" );

    $mech->text_contains(
        "Attribute (lc_src) does not pass the type constraint because: Valid"
            . " language codes are 2 or 5 characters"
        , "Empty body error in content"
        );
}

sub can_estimate_job_cost {
    my $fields = dummy_job_hash_frontend();
    $fields->{estimate_only} = 1;

    $mech->get('/mygengo/job');
    $mech->submit_form_ok({
        fields => $fields
        }, "Requested Job estimate" );

    $mech->content_like( qr{Credits: \d+\.\d+}, "Has credits" );
    $mech->content_like( qr{Unit Count: \d+}, "Has unit count" );
}

sub fields_are_preserved_after_estimating_cost_for_new_job {
    my $fields = dummy_job_hash_frontend();
    $fields->{estimate_only} = 1;

    $mech->get('/mygengo/job');
    $mech->submit_form_ok({
        fields => $fields
        }, "Requested Job estimate" );

    my $form = shift @{$mech->forms()};

    foreach my $field ( keys %$fields ) {
        next if $field =~ /^estimate_only$/; # This resets

        my $form_field = $form->find_input("^$field");
        ok( $form_field, "Has form field '$field'" )
            or next;

        my $val = $fields->{$field};
        my $form_value = $form_field->value();
        is( $form_value, $val, "Value '$field' was preserved" );
    }
}
