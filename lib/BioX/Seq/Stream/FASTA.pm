package BioX::Seq::Stream::FASTA;

use strict;
use warnings;

sub _check_type {

    my ($class,$self) = @_;
    return substr($self->{buffer},0,1) eq '>';

}

sub _init {

    my ($self) = @_;

    # First two bytes should not contain line ending chars
    die "Missing ID in initial header (check file format)\n"
        if ($self->{buffer} =~ /[\r\n]/);
    my $fh = $self->{fh};
    $self->{buffer} .= <$fh>;

    # detect line endings for text files based on first line
    # (other solutions, such as using the :crlf layer or s///
    # instead of chomp may be marginally more robust but slow
    # things down too much)
    if ($self->{buffer} =~ /([\r\n]{1,2})$/) {
        $self->{rec_sep} = $1;
    }
    else {
        die "Failed to detect line endings\n";
    }
    local $/ = $self->{rec_sep};

    # Parse initial header line
    chomp $self->{buffer};
    if ($self->{buffer} =~ /^>(\S+)\s*(.+)?$/) {
        $self->{next_id}   = $1;
        $self->{next_desc} = $2;
        $self->{buffer} = undef;
    }
    else {
        die "Failed to parse initial FASTA header (check file format)\n";
    }

    return;

}

sub next_seq {
    
    my ($self) = @_;

    my $fh   = $self->{fh};
    my $id   = $self->{next_id};
    my $desc = $self->{next_desc};
    my $seq = '';

    local $/ = $self->{rec_sep};
    
    my $line = <$fh>;

    while ($line) {

        chomp $line;

        # match next record header
        if ($line =~ /^>(\S+)\s*(.+)?$/) {

            $self->{next_id}   = $1;
            $self->{next_desc} = $2;
            return BioX::Seq->new($seq, $id, $desc);

        }
        else {
            $seq .= $line;
        }

        $line = <$fh>;

    }

    # should only reach here on last read
    if (defined $self->{next_id}) {
        delete $self->{next_id};
        delete $self->{next_desc};
        return BioX::Seq->new($seq, $id, $desc);
    }
    return undef;

}

1;
