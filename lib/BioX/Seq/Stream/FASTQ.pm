package BioX::Seq::Stream::FASTQ;

use strict;
use warnings;

sub _check_type {

    my ($class,$self) = @_;
    return substr($self->{buffer},0,1) eq '@';

}

sub _init {

    my ($self) = @_;

    # First two bytes should not contain line ending chars
    die "Missing ID in initial header (check file format)\n"
        if ($self->{buffer} =~ /[\r\n]/);
    my $fh = $self->{fh};
    $self->{buffer} .= <$fh>;

    return;
    
}

sub next_seq {
    
    my ($self) = @_;
    my $fh = $self->{fh};

    my $line = $self->{buffer} // <$fh>;
    return undef if (! defined $line);
    chomp $line;

    my ($id, $desc) = ($line =~ /^\@(\S+)\s*(.+)?$/);
    die "Bad FASTQ ID line\n" if (! defined $id);

    # seq and qual can be multiline (although rare)
    # qual is tricky since it can contain '@' but we compare to the
    # sequence length to know when to stop parsing (must be equal lengths)
    my $seq = <$fh> // die "Bad or missing FASTQ sequence";
    chomp $seq;

    SEQ:
    while (my $line = <$fh>) {
        chomp $line;
        last SEQ if ($line =~ /^\+/);
        $seq .= $line;
    }

    my $seq_len = length $seq;

    QUAL:
    my $qual = <$fh> // die "Bad or missing FASTQ format";
    chomp $qual;

    while ( (length($qual) < $seq_len) && defined (my $line = <$fh>) ) {
        chomp $line;
        $qual .= $line;
    }
    die "Bad FASTQ quality length" if ($seq_len != length($qual));

    $self->{buffer} = undef;

    return BioX::Seq->new($seq, $id, $desc, $qual);

}

1;
