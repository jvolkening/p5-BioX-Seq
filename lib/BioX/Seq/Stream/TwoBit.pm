package BioX::Seq::Stream::TwoBit;

use strict;
use warnings;
use POSIX qw/ceil/;

use constant MAGIC => 0x1a412743;
use constant LE_MAGIC_S => pack('C2', 0x43, 0x27);
use constant LE_MAGIC_L => pack('C2', 0x41, 0x1a);
use constant BE_MAGIC_S => pack('C2', 0x1a, 0x41);
use constant BE_MAGIC_L => pack('C2', 0x27, 0x43);

my @byte_map = map {
    my $i = $_; join '', map {qw/T C A G/[ vec(chr($i),3-$_,2) ]} 0..3
} 0..255;

sub _check_type {

    my ($class,$self) = @_;
    return 1 if $self->{buffer} eq LE_MAGIC_S;
    return 1 if $self->{buffer} eq BE_MAGIC_S;
    return 0;

}

sub _init {

    my ($self) = @_;
   
    binmode $self->{fh};
    my $fh = $self->{fh};

    # Determine endianness
    my $magic = $self->{buffer} . _safe_read( $fh, 2 );
    my $byte_order = unpack('V', $magic) == MAGIC ? 'V'
                   : unpack('N', $magic) == MAGIC ? 'N'
                   : die "File signature check failed";
    $self->{byte_order} = $byte_order;

    # Unpack rest of header
    my ($version, $seq_count, $reserved) = unpack "$byte_order*",
        _safe_read( $fh, 12 );
    die "File header check failed" if ($version != 0 || $reserved != 0);
    $self->{seq_count} = $seq_count;

    # Build index
    my $last_name;
    my $buf;
    my @index;
    for (1..$self->{seq_count}) {
        read $fh, $buf, 1;
        read $fh, $buf, ord($buf);
        my $name = $buf;
        read $fh, $buf, 4;
        my $offset   = unpack $byte_order, $buf;
        die "$name already defined" if (defined $self->{index}->{$name});
        push @index, [$name, $offset];
    }
    $self->{index} = [@index];
    $self->{curr_idx} = 0;

    return;

}

sub next_seq {
    
    my ($self) = @_;

    return undef if ($self->{curr_idx} >= $self->{seq_count});

    my $seq = $self->fetch_record( $self->{curr_idx} );
    ++$self->{curr_idx};
    return $seq;

}

sub _safe_read {

    my ($fh, $bytes) = @_;
    my $r = read($fh, my $buffer, $bytes);
    die "Unexpected read length" if ($r != $bytes);
    return $buffer;

}

sub fetch_record {

    my ($self, $idx) = @_;

    my ($id,$offset) = @{ $self->{index}->[$idx] };
    my $byte_order = $self->{byte_order};
    my $fh         = $self->{fh};
    seek $fh, $offset, 0;
    
    my $seq_len = unpack "$byte_order*", _safe_read($fh, 4);
    my $N_count = unpack "$byte_order*", _safe_read($fh, 4);
    my @N_data  = unpack "$byte_order*", _safe_read($fh, 4 * $N_count * 2);
    my %N_lens;
    @N_lens{ @N_data[0..$N_count-1] } = @N_data[$N_count..$#N_data];

    my $mask_count = unpack "$byte_order*", _safe_read($fh, 4);
    my @mask_data  = unpack "$byte_order*", _safe_read($fh, 4 * $mask_count * 2);
    my %mask_lens;
    @mask_lens{ @mask_data[0..$mask_count-1] } = @mask_data[$mask_count..$#mask_data];

    # reserved field
    my $reserved = unpack "$byte_order*", _safe_read($fh, 4);

    my $to_read  = ceil($seq_len/4);

    # this is the speed bottleneck, but haven't found a better way yet
    my $string;
    $string .= $byte_map[$_] for (unpack "C*", _safe_read($fh, $to_read));

    $string = substr $string, 0, $seq_len;

    # N and mask
    for (keys %N_lens) {
        my $len = $N_lens{$_};
        substr($string, $_, $len) = 'N' x $len;
    }
    for (keys %mask_lens) {
        my $len = $mask_lens{$_};
        substr($string, $_, $len) ^= (' ' x $len);
    }
    return BioX::Seq->new($string, $id, '');

}

1;
