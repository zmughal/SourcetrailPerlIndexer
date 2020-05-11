package t::indexer_fp;

use strict;
use warnings;

use File::Spec;
use FindBin;
use JSON;
use Mock::Quick;
use Test::Exit;
use Test::More tests => 3;

use lib File::Spec->catfile( $FindBin::Bin, '..' );
use indexer qw(:all);

my $CALL       = $indexer::REFERENCE_CALL;
my $EXPLICIT   = $indexer::DEFINITION_EXPLICIT;
my $FUNCTION   = $indexer::SYMBOL_FUNCTION;
my $GLOBAL_VAR = $indexer::SYMBOL_GLOBAL_VARIABLE;
my $IMPLICIT   = $indexer::DEFINITION_IMPLICIT;
my $IMPORT     = $indexer::REFERENCE_IMPORT;
my $INCLUDE    = $indexer::REFERENCE_INCLUDE;
my $PACKAGE    = $indexer::SYMBOL_PACKAGE;
my $USAGE      = $indexer::REFERENCE_USAGE;

my ( $file, $language, @references, %references, @symbols, %symbols );

sub decode_symbol {
    my $symbol_ref = decode_json(shift);
    my $name_ref   = $symbol_ref->{name_elements};
    return $name_ref->[-1]{prefix} . join( '::', map { $name_ref->[$_]{name} } keys @{$name_ref} );
}

sub record_reference {
    my ( $from, $to, $kind ) = @_;

    push @{ $references{$from}{$to} }, scalar @references;
    push @references, { K => $kind };

    return $references{$from}{$to}[-1];
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
    recordLocalSymbol          => \&record_symbol,
    recordSymbol               => \&record_symbol,
    recordSymbolDefinitionKind => sub { $symbols[ $_[0] ]{D} = $_[1] },
    recordSymbolKind           => sub { my ( $id, $kind ) = @_; $symbols[$id]{K} = $kind },
    recordLocalSymbolLocation  => \&record_symbol_location,
    recordSymbolLocation       => \&record_symbol_location,
    recordReference            => \&record_reference,
    recordReferenceLocation    => \&record_reference_location,
);

my $source = '';
my @expect;

@symbols = %symbols = ();
$source = <<'CODE';
sub test1;
sub test2();
sub test3 : attr1() : attr2;
sub test4() : attr1() : attr2;
sub test5 {}
sub test6() {}
sub test7 : attr1() : attr2 {}
fun test8() : attr1() : attr2 {}
fun test9($arg1) {}
sub testa :attr1() :attr2 ($arg2) {}
sub testb :prototype() ($arg3) {}
CODE

@expect = (
    { D => $IMPLICIT, K => $PACKAGE, },    # main
    ( map { D => $EXPLICIT, F => 1, K => $FUNCTION, LB => $_, CB => 5, LE => $_, CE => 9, }, ( 1 .. 10 ) ),  # test 1..a
    { D => $IMPLICIT, },                                                                                     # arg2
    { D => $EXPLICIT, F => 1, K => $FUNCTION, LB => 11, CB => 5, LE => 11, CE => 9, },                       # test b
    { D => $IMPLICIT, },                                                                                     # arg3
);
index_source_file( \$source );
is_deeply(
    [ sort keys %symbols ],
    [ qw($main::arg2 $main::arg3 main), map { "main::test$_" } ( 1 .. 9, 'a' .. 'b' ) ],
    'sub symbols'
);
is_deeply( \@symbols, \@expect, 'sub definitions' );

done_testing;
