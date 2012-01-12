use strict;
use warnings;

use CataGengo;

my $app = CataGengo->apply_default_middlewares(CataGengo->psgi_app);
$app;

