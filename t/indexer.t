package t::indexer;

use strict;
use warnings;

use File::Spec;
use FindBin;
use JSON;
use Mock::Quick;
use Test::Exit;
use Test::More tests => 10;

use lib File::Spec->catfile( $FindBin::Bin, '..' );
use indexer qw(:all);

my $EXPLICIT = $indexer::DEFINITION_EXPLICIT;
my $IMPLICIT = $indexer::DEFINITION_IMPLICIT;
my $IMPORT   = $indexer::REFERENCE_IMPORT;
my $INCLUDE  = $indexer::REFERENCE_INCLUDE;
my $PACKAGE  = $indexer::SYMBOL_PACKAGE;

my ( $file, $language, @references, %references, @symbols, %symbols );

sub decode_symbol {
	my $symbol_ref = decode_json(shift);
	my $name_ref   = $symbol_ref->{name_elements};
	return join( '::', map { $name_ref->[$_]{name} } keys @{$name_ref} );
}

sub record_reference {
	my ( $from, $to, $kind ) = @_;

	if ( !exists $references{$from}{$to} ) {
		$references{$from}{$to} = scalar @references;
		push @references, { K => $kind };
	}

	return $references{$from}{$to};
} ## end sub record_reference

sub record_reference_location {
	my $i = shift;

	$references[$i] = { %{ $references[$i] }, F => shift, LB => shift, CB => shift, LE => shift, CE => shift };
	return;
} ## end sub record_reference_location

sub record_symbol {
	my ($key) = @_;

	$key = decode_symbol($key);
	if ( !exists $symbols{$key} ) {
		$symbols{$key} = scalar @symbols;
		push @symbols, { D => $IMPLICIT };
	}

	return $symbols{$key};
} ## end sub record_symbol

sub record_symbol_location {
	my $i = shift;

	$symbols[$i] = { %{ $symbols[$i] }, F => shift, LB => shift, CB => shift, LE => shift, CE => shift };

	return;
} ## end sub record_symbol_location

# ---------- Tests start here ----------

is( exit_code { index_source_file('') }, 2, 'no source' );
$PPI::Document::errstr = '';    ## no critic (ProhibitPackageVars)

my $control = qtakeover(
	indexer => ( recordFile => sub { $file = shift; return 1 }, recordFileLanguage => sub { $language = $_[1] } ),
	recordSymbol               => \&record_symbol,
	recordSymbolDefinitionKind => sub { $symbols[ $_[0] ]{D} = $_[1] },
	recordSymbolKind           => sub { my ( $id, $kind ) = @_; $symbols[$id]{K} = $kind },
	recordSymbolLocation       => \&record_symbol_location,
	recordReference            => \&record_reference,
	recordReferenceLocation    => \&record_reference_location,
);

my $source = '';
index_source_file( \$source );

is( $file,     \$source, 'recordFile' );
is( $language, 'perl',   'recordFileLanguage' );
is_deeply( [ sort keys %symbols ], [qw(main)], 'recordSymbol' );
is_deeply( \@symbols, [ { D => $IMPLICIT, K => $indexer::SYMBOL_PACKAGE } ], 'recordSymbolKind' );

# package NAMESPACE
# package NAMESPACE VERSION
# package NAMESPACE BLOCK
# package NAMESPACE VERSION BLOCK

$source = <<'CODE';
package test1;
package test2 v1.0;
package test3 { 1; }
package test4 v1.1 { 1; }
{ package test5; }
package main;
CODE

my @expect = (
	{ D => $EXPLICIT, F => 1, K => $PACKAGE, LB => 6, CB => 9,  LE => 6, CE => 12 },    # main
	{ D => $EXPLICIT, F => 1, K => $PACKAGE, LB => 1, CB => 9,  LE => 1, CE => 13 },    # test1
	{ D => $EXPLICIT, F => 1, K => $PACKAGE, LB => 2, CB => 9,  LE => 2, CE => 13 },    # test2
	{ D => $EXPLICIT, F => 1, K => $PACKAGE, LB => 3, CB => 9,  LE => 3, CE => 13 },    # test3
	{ D => $EXPLICIT, F => 1, K => $PACKAGE, LB => 4, CB => 9,  LE => 4, CE => 13 },    # test4
	{ D => $EXPLICIT, F => 1, K => $PACKAGE, LB => 5, CB => 11, LE => 5, CE => 15 },    # test5
);
index_source_file( \$source );
is_deeply( [ sort keys %symbols ], [qw(main test1 test2 test3 test4 test5)], 'package symbols' );
is_deeply( \@symbols, \@expect, 'package definitions' );

# require VERSION
# require NAMESPACE
# require FILENAME
# use Pragma
# use Module VERSION LIST
# use Module VERSION
# use Module LIST
# use Module
# use VERSION

@symbols = %symbols = ();
$source = <<'CODE';
require v5.10;
require test1;
require '_version.pm';
use strict;
use test2 v1.0 ();
use test3 v1.1;
use test4 ();
use test5;
use v5.10.1;
CODE

@expect = ( ( { D => $IMPLICIT, K => $PACKAGE, } ) x 6 );
my @expect_refs = (
	{ K => $INCLUDE, F => 1, LB => 2, CB => 9, LE => 2, CE => 13, },    # test1
	{ K => $IMPORT,  F => 1, LB => 5, CB => 5, LE => 5, CE => 9, },     # test2
	{ K => $IMPORT,  F => 1, LB => 6, CB => 5, LE => 6, CE => 9, },     # test3
	{ K => $IMPORT,  F => 1, LB => 7, CB => 5, LE => 7, CE => 9, },     # test4
	{ K => $IMPORT,  F => 1, LB => 8, CB => 5, LE => 8, CE => 9, },     # test5
);
index_source_file( \$source );
is_deeply( [ sort keys %symbols ], [qw(main test1 test2 test3 test4 test5)], 'require and use symbols' );
is_deeply( \@symbols,    \@expect,      'require and use definitions' );
is_deeply( \@references, \@expect_refs, 'require and use references' );

1;