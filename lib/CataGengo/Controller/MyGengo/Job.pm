package CataGengo::Controller::MyGengo::Job;
use feature 'say';
use Data::Dumper;

use Moose;
use namespace::autoclean;

BEGIN {
    extends
        'Catalyst::Controller::REST'
        , 'CataGengo::Controller::MyGengo'
        ;

    # Don't attempt to (de)serialize text/html
    __PACKAGE__->config->{default} = 'text/html';
    __PACKAGE__->config->{map}->{'text/html'} = [ 'View', 'Web' ];
}

use WebService::MyGengo::Job;
use DateTime;
use Catalyst::Exception;

=head1 DESCRIPTION

Controller containing Jobs-related endpoints.

=head1 ATTRIBUTES

=head2 client

An instance of the L<CataGengo::Model::MyGengo>

Populated by the `auto` method.

todo Rename that model class...

=cut
has 'client' => ( is => 'rw' , isa => 'Object' ); # todo lazy.

=head2 all_jobs_cache_key

The key under which to store the list of all Jobs in the
session.

=cut
has all_jobs_cache_key => (
    is          => 'ro'
    , isa       => 'Str'
    , default   => 'WebService::MyGengo::Jobs'
    );

=head1 ENDPOINTS

=head2 default

Prevent `default` from intercepting calls to '/mygengo/job'

See L<http://grokbase.com/t/lists.scsys.co.uk/catalyst/2010/01/catalyst-default-running-over-chained/264lkzoyh2xsmuvsserczbayz35a>

=cut
sub default :Private {}

=head2 auto

Automatically called by Catalyst.

Populate `$self->client`.

=cut
sub auto :Private {
    my ( $self, $c ) = ( shift, @_ );
    $self->client( $c->model('MyGengo') );
}

=head2 new_job | GET,POST /mygengo/job

Displays a form for creating a new Job.

=cut
sub new_job :PathPart('job') :Chained('../mygengo') :ActionClass('REST') :Args(0) { }

=head2 new_job_GET

We're only displaying the new Job template, so this is a no-op

=cut
sub new_job_GET {
    my ( $self, $c ) = ( shift, @_ );

    my $key = 'WebService::MyGengo::LanguagePairs';

    my $language_pairs = $c->session->{ $key };
    !$language_pairs and
        $language_pairs = $self->client->get_service_language_pairs();
    $language_pairs and $c->session->{ $key } = $language_pairs;

    $c->stash(
        language_pairs => $language_pairs
        );

    # todo I don't remember having to do this before. Hm.
    $c->detach('/end');
}

=head2 new_job_POST

Creates a new Job and redirects the client to it's details page.

=cut
sub new_job_POST {
    my ( $self, $c ) = ( shift, @_ );

    my $client = $self->client;
    my %params = %{$c->req->params};

    my $pair    = delete $params{language_pair};
    my ($src,$tgt,$tier) = split /::/, $pair;

    $params{lc_src} = $src;
    $params{lc_tgt} = $tgt;
    $params{tier}   = $tier;

    my $job = WebService::MyGengo::Job->new( \%params );

    # todo This is a hack, but hey, it's a demo.
    if ( $params{estimate_only} ) {
        $job = shift @{$client->determine_translation_cost( $job )};
        $c->stash( job => $job );
        return $self->new_job_GET( $c );
    }

    $job = $client->submit_job( $job );

    if ( !$job ) {
        $c->log->error("Error creating Job: ".Dumper($client->last_response));
        Catalyst::Exception->throw("Error creating new Job.");
    }

    # Push the Job into our list of all Jobs, only if theyve already been
    #   fetched.
    my $key     = $self->all_jobs_cache_key;
    push @{ $c->session->{ $key } }, $job;

    # Send them to the Job details page
    return $c->res->redirect( $c->uri_for(
        $self->action_for('job'), [ $job->id ]
        ) );
}

=head2 load_job | /mygengo/job/*

Accepts a Job ID as an argument and populates `$c->stash->{job}` with the Job.

All endpoints that accept a Job as an argument should chain off this method.

=cut
sub load_job :PathPart('job') :Chained('../mygengo') :CaptureArgs(1) {
    my ( $self, $c, $id ) = ( shift, @_ );

    my $job = $self->_get_job( $c, $id );

    # Bail if we can't find this Job
    ( !$job ) and Catalyst::Exception->throw("Job '".$id."' not found.");
    $c->stash(
        job => $job
        );
}

=head2 job | GET,PUT,DELETE /mygengo/job/*

Endpoint for actions relating to a single Job.

=cut
sub job :PathPart('') :Chained('load_job') :ActionClass('REST') :Args(0) { }

=head2 job_GET 

Display details for the given Job.

todo AJAX-ify

=cut
sub job_GET {
    my ( $self, $c ) = ( shift, @_ );
    # todo I don't remember having to do this before. Hm.
    $c->detach('/end');
}

=head2 job_PUT

Update the given Job and redirect to the Job details view.

Processes `$c->req->params` as well as `$c->req->data` in case this was a
form submission instead of an AJAX call (hack.)

todo AJAX-ify

=cut
sub job_PUT {
    my ( $self, $c ) = ( shift, @_ );

    my $client = $self->client;

    # todo Hack. Support REST as well as form submit params
    my $params  = $c->req->params;
    my $data    = $c->req->data;
    
    $data and @$params{ keys %$data } = values %$data;

    my $job     = $c->stash->{job};
    my $action  = $params->{action};

    my $res;
    if ( $action eq 'revise' ) {
        $res = $client->request_job_revision( $job
            , $params->{'revise-comment'}
            );
    }
    elsif ( $action eq 'approve' ) {
        $res = $client->approve_job( $job
            , $params->{'approve-rating'}, $params->{'approve-for_translator'}
            , $params->{'approve-for_mygengo'}, $params->{'approve-public'}
            );
    }
    elsif ( $action eq 'reject' ) {
        $res = $client->reject_job( $job
            , $params->{'reject-reason'}, $params->{'reject-comment'}
            , $params->{'reject-captcha'}, $params->{'reject-follow_up'}
            );
    }
    else {
        Catalyst::Exception->throw( "Invalid action: $action" );
    }

    if ( !$res ) {
        my $msg = "Error ${action}-ing Job.";
        $c->log->error($msg.": ".Dumper($client->last_response));
        Catalyst::Exception->throw( $msg );
    }
    
    delete $c->session->{ ref($job)."::".$job->id };
    return $c->res->redirect( $c->uri_for(
        $self->action_for('job'), [ $job->id ]
        ) );
}

=head2 job_DELETE

Deletes the given Job and redirects to the Jobs list.

todo AJAX-ify

=cut
sub job_DELETE {
    my ( $self, $c ) = ( shift, @_ );

    my $client = $self->client;
    my $job = $c->stash->{job};

    my $res = $self->_delete_job( $c, $job );
    if ( ! $res ) {
        my $msg = "Error cancelling Job.";
        $c->log->error($msg.": ".Dumper($client->last_response));
        # todo More informative error message
        Catalyst::Exception->throw("Error cancelling Job.");
    }
    
    return $c->res->redirect( $c->uri_for( $self->action_for('jobs') ) );
}

=head2 load_job_actions | /mygengo/job_actions/*

Accepts a Job ID as an argument and populates `$c->stash->{job}` with the Job.

All endpoints that are used to workaround browsers not sending PUT and DELETE
should chain off this method.

=cut
sub load_job_actions :PathPart('job_actions') :Chained('../mygengo') :CaptureArgs(1)
{
    return shift->load_job( @_ );
}

=head2 job_put | POST /mygengo/job_actions/*/put

Regular HTML forms don't (usually) send PUT so offer this as a synonym for
PUT /mygento/job/*

=cut
sub job_put :PathPart('put') :Chained('load_job_actions') :Args(0) {
    return shift->job_PUT( @_ );
}

=head2 job_delete | POST /mygengo/job_actions/*/delete

Regular HTML forms don't (usually) send DELETE so offer this as a synonym for
DELETE /mygento/job/*

=cut
sub job_delete :PathPart('delete') :Chained('load_job_actions') :Args(0) {
    return shift->job_DELETE( @_ );
}

=head2 comment | POST /mygengo/job/*/comment

Endpoint for actions relating to Comments.

=cut
sub comment :Chained('load_job') :ActionClass('REST') Args(0) { }

=head2 comment_POST

Adds a new comment to the given Job.

Redirects to the Job details page.

todo AJAX-ize

=cut
sub comment_POST {
    my ( $self, $c ) = ( shift, @_ );

    my $client = $self->client;

    my $body = $c->req->params->{comment_body}
        or Catalyst::Exception->throw("Empty comment body.");

    my $job = $c->stash->{job};
    my $res = $client->add_job_comment( $job, $body );

    # todo Standardize the exception handling
    if ( !$res ) {
        my $msg = "Error in add_comment.";
        $c->log->error("$msg: ".Dumper($client->last_response));
        Catalyst::Exception->throw($msg);
    }

    # todo AJAX-ize
    delete $c->session->{ ref($job)."::".$job->id };
    $c->res->redirect( $c->uri_for(
        $self->action_for('job'), [ $job->id ]
        ) );
}

=head2 jobs | GET /mygengo/jobs

Endpoint for actions affecting all Jobs

todo Support bulk-edit API actions.

todo Should arguably be in its own class.

=cut
sub jobs :PathPart('jobs') :Chained('../mygengo') :ActionClass('REST') :Args(0) { }

=head2 jobs_GET

Displays all Jobs in a table.

Accepts filter parameters: status, timestamp_after, count

Defaults to fetching the first 100 jobs, irregardless of status or timestamp.

Defaults to sorting newest-job-first.

=cut
sub jobs_GET {
    my ( $self, $c ) = ( shift, @_ );

    my $status_filter       = $c->req->params->{status};
    my $timestamp_filter    = $c->req->params->{timestamp_after};
    my $count_filter        = $c->req->params->{count} || 100;

    my $client  = $self->client;
    my $key     = $self->all_jobs_cache_key;

    # Redirect so it clears the query param out of their address bar
    if ( $c->req->params->{refresh} ) {
        delete $c->session->{ $key };
        $c->res->redirect( $c->uri_for( $self->action_for('jobs') ) );
        $c->detach();
    }

    # This would eventually be handled in the model layer
    my $jobs = $c->session->{ $key };
    !( ref($jobs) and scalar(@$jobs) ) and $c->session->{ $key } = 
        $client->search_jobs( $status_filter, $timestamp_filter, $count_filter );

    $c->stash(
        jobs => $c->session->{ $key }
        );
    
    # Otherwise it tries to serialize the results
    $c->detach('/end');
}

=head2 _get_job( $id )

Utility method to fetch a Job from the session, or from the model.

The Job will be cached automatically after being fetched from the model.

Returns a Job on success, false on failure.

This could eventually be handled in the model layer or
using the Session.

=cut
sub _get_job {
    my ( $self, $c, $id ) = ( shift, @_ );

    my $key = "WebService::MyGengo::Job::$id";

    # Redirect so it clears the query param out of their address bar
    if ( $c->req->params->{refresh} ) {
        delete $c->session->{ $key };
        $c->res->redirect( $c->uri_for( $self->action_for('job'), [ $id ] ) );
        $c->detach();
    }

    my $job = $c->session->{ "WebService::MyGengo::Job::$id" };

    if ( !$job ) {
        $job = $self->client->get_job( $id, 0 );
        !$job and return undef;

        # If the Job is approved, get it's revision list
        if ( $job->is_approved ) {
            $job = $self->client->get_job( $id, 1, 1 );
        }
        # Otherwise just the comments will do
        else {
            $job = $self->client->get_job( $id, 1, 0 );
        }
        $c->session->{ $key } = $job;
    }

    return $job;
}

=head2 _delete_job( $job )

Utility method to remove a Job from the session

This could eventually be handled in the model layer or
using the Session.

=cut
sub _delete_job {
    my ( $self, $c, $job ) = ( shift, @_ );

    my $key = "WebService::MyGengo::Job::".$job->id;

    my $res = $self->client->delete_job( $job );
    $res and delete $c->session->{ $key };

    # Remove the Job from the list of all Jobs
    $key        = $self->all_jobs_cache_key;
    my $jobs    = $c->session->{ $key };
    @$jobs = grep { $_->id != $job->id } @$jobs;
    $c->session->{ $key } = $jobs;

    return $res;
}


__PACKAGE__->meta->make_immutable;

1;

=head1 AUTHOR

Nathaniel Heinrichs

=head1 LICENSE

Copyright (c) 2011, Nathaniel Heinrichs <nheinric-at-cpan.org>.
All rights reserved.

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
