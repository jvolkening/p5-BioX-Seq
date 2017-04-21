#!/usr/bin/perl

use strict;
use warnings;

use File::Compare;
use Test::More;
use FindBin;
use BioX::Seq;
use BioX::Seq::Stream;
use BioX::Seq::Fetch;

chdir $FindBin::Bin;

my $test_fa  = 'test_data/test.fa';
my $test_fq  = 'test_data/test.fq';
my $test_gz  = 'test_data/test2.fa.gz';
my $test_cmp = 'test_data/test2.fa.gz.fai.cmp';
my $test_fai = 'test_data/test2.fa.gz.fai';

my @tmp_files = (
    $test_fai,
);

my $obj = BioX::Seq->new;

ok ($obj->isa('BioX::Seq'), "returned BioX::Seq object");

$obj->seq( 'AAGT' );
$obj .= 'TTCAAA';
$obj->rev_com();
ok ("$obj" eq 'TTTGAAACTT', "concat and rc");

my $tr = $obj->translate(5);
ok ($obj->seq() eq 'TTTGAAACTT', "context transform");
ok ($tr->seq() eq 'VS', "translater");

my $fq = $obj->as_fastq;
ok (! $fq, "missing ID");
$obj->id('test_seq');

my $sub = $obj->rev_com->range(3,10);
ok ("$sub" eq 'GTTTCAAA', "range");
$sub = $obj->rev_com->range(3,11);
ok (! defined $sub, "out of range");

$fq = $obj->rev_com->as_fastq(21);
ok ($fq eq "\@test_seq\nAAGTTTCAAA\n+\n6666666666\n", "as FASTQ");
$obj->desc("testing it");
my $fa = $obj->as_fasta(4);
ok ($fa eq ">test_seq testing it\nTTTG\nAAAC\nTT\n", "as FASTA");


my $parser = BioX::Seq::Stream->new($test_fa);

ok ($parser->isa('BioX::Seq::Stream::FASTA'), "returned BioX::Seq::Stream::FASTA object");

my $seq = $parser->next_seq;
ok ($seq->isa('BioX::Seq'), "returned BioX::Seq object");

ok ($seq->id eq 'Test1|someseq', "read seq ID");
ok ($seq->seq eq 'AATGCAAGTACGTAAGACTTATAGCAGTAGGATGGAATGATAGCCATAG', "read seq ");
ok ($seq->desc eq 'This is a test of the emergency broadcast system', "read desc");
ok (! defined $seq->qual, "undefined qual");

$seq = $parser->next_seq;
ok ($seq->seq eq 'TTAGATTGATTTTTAGATAGGA', "read 2nd seq ");
$seq = $parser->next_seq;
ok ($seq->seq eq 'GTTAGAGCCAGGAACGAGAACGA', "read 3rd seq ");
$seq = $parser->next_seq;
ok ($seq->seq eq 'WWFWWFWWFWWFWWFWWFWWFWWFWWF', "read 4th seq ");
$seq->translate();
ok ($seq->seq eq 'WWFWWFWWFWWFWWFWWFWWFWWFWWF', "invalid translate");
my $invalid = $seq->translate();
ok (! defined $invalid, "invalid translate undef");

open my $in, '<', $test_fq;
$parser = BioX::Seq::Stream->new($in);

ok ($parser->isa('BioX::Seq::Stream::FASTQ'), "returned BioX::Seq::Stream::FASTQ object");

$seq = $parser->next_seq;
ok ($seq->seq eq 'ATTGAGGGGATTGAGATAGGGTGGAGTANNNTGGAT', "read seq");
ok ($seq->id eq 'Test1', "read id");
ok ($seq->desc eq 'some description here', "read desc");
ok ($seq->qual eq '433229299291929292922291919292292211', "read qual");

$seq = $parser->next_seq;
ok ($seq->seq eq 'ATTGAGAATGACCGATAAACT', "read 2nd seq");
ok ($seq->qual eq '@11944491019494440111', "read 2nd qual");

# this one should throw error
eval {
    $seq = $parser->next_seq;
};
ok ($seq->seq eq 'ATTGAGAATGACCGATAAACT', "seq unchanged");

$parser = BioX::Seq::Fetch->new($test_gz);
ok(! compare($test_fai, $test_cmp), "Compare indices" );

$seq = $parser->fetch_seq('Test1|someseq', 28 => 33);
ok( $seq->seq eq 'TAGGAT', "fetch seq match 1" );

$seq = $parser->fetch_seq('Prot1', 1 => 1);
ok( $seq->seq eq 'W', "fetch seq match 2" );

$seq = $parser->fetch_seq('Test3/yetanother');
ok( $seq->seq eq 'GTTAGAGCCAGGAACGAGAACGA', "fetch seq match 3" );

my @ids = $parser->ids;
ok( scalar(@ids) == 4, "ID count" );
ok( $ids[1] eq 'Test1|another', "ID comparison" );
my $l = $parser->length($ids[2]);
ok( $parser->length($ids[2]) == 23, "length comparison" );

unlink $_ for (@tmp_files);

done_testing();
exit;
