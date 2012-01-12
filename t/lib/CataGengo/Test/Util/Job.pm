package CataGengo::Test::Util::Job;

use strict;
use warnings;

=head1 NAME

CataGengo::Test::Util::Job - A utility class for working with dummy Jobs

=cut
use WebService::MyGengo::Job;
use WebService::MyGengo::Comment;

use CataGengo::Test::Util::Client;

use Test::More; # Just for diag routines
use Exporter;

use vars qw(@ISA @EXPORT);
use base qw(Exporter);

@EXPORT = qw(create_dummy_job dummy_job_hash dummy_job_hash_frontend dummy_job dummy_comments teardown_jobs);

# TODO
use Data::Dumper;
use feature 'say';

my @_dummies = ();

=head1 METHODS

=head2 dummy_job_hash()

Return a hash of fields suitable for creating a dummy Job.

See: L<http://mygengo.com/api/developer-docs/payloads/>

=cut
sub dummy_job_hash {
    return {
        "mt"            => 0
        , "lc_tgt"      => "ja"
        , "body_tgt"    =>  ""
        # body_src should always be unique
        , "body_src"    => rand()." ba-weep-gra-na-weep-ninny-bong"
        , "tier"        => "standard"
        , "custom_data" => rand()." custom data"
        , "lc_src"      => "en"
        , "auto_approve"=> "0"
        , "slug"        => rand()." What does this do?"
        };
}

=head2 dummy_job_hash_frontend()

Return a hash of fields suitable for creating a dummy Job via the frontend web
form.

=cut
sub dummy_job_hash_frontend {
    return {
        language_pair   => 'en::es::standard'
        , body_src      => rand()."This is emphatically NOT a pen."
        , comment       => "This is my homework, please xlate carefully."
        , custom_data   => rand()
        , force         => 1
        , use_preferred => 1
        , auto_approve  => 1
        };
}

=head2 dummy_job()

Returns a L<WebService::MyGengo::Job> created from a `dummy_job_hash`

=cut
sub dummy_job {
    return WebService::MyGengo::Job->new( dummy_job_hash() );
}

=head2 dummy_comments()

Returns a reference to an array of L<WebService::MyGengo::Comment> objects.

=cut
sub dummy_comments {
    return [
        WebService::MyGengo::Comment->new(rand().' Comment1')
        , WebService::MyGengo::Comment->new(rand().' Comment2')
        ];
}

=head2 create_dummy_job( $client )

Submit a Job from `dummy_job` to the API and return it.

The Job will automatically be placed in a list of Jobs to be deleted at the end
of the test run.

=cut
sub create_dummy_job {
    my $job = dummy_job();

    my $client = client();

    my $new_job = $client->submit_job( $job );
    if ( !$new_job ) {
        diag "Failed to submit new Job: ".Dumper($client->last_response);
        return undef;
    }

    # We can only POST the comment body
    foreach ( @{ dummy_comments() } ) {
        my $res = $client->add_job_comment( $new_job, $_ );
        if ( !$res ) {
            diag "Failed to add Job comment: ".Dumper($client->last_response);
            return 0;
        }
    }

    # Fetch comments as well, we often want them
    $new_job = $client->get_job( $new_job->id, 1 );

    push @_dummies, $new_job;
    return $new_job;
}

=head2 teardown_jobs()

When called at the end of a test run, will attempt to delete any dummy Jobs
created during testing from the API.

B<Note:> If a Job is no longer in 'available' status it cannot be deleted. You
will need to remove it from the sandbox by hand if you are using live sandbox
testing.

=cut
sub teardown_jobs {
    client()->delete_job( $_ ) foreach (@_dummies);
}


1;
