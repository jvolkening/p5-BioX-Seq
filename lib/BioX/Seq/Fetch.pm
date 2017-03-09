package BioX::Seq::Fetch;

use 5.012;
use strict;
use warnings;

use BioX::Seq;

use constant MAGIC_GZIP => pack('C3', (0x1f, 0x8b, 0x08));

sub new {

    my ($class,$fn) = @_;

    die "Can't find or read input filename"
        if (! defined $fn || ! -e $fn);

    my $self = bless {fn => $fn}, $class;

    open my $fh, '<', $fn or die "Error opening $fn for reading: $!\n";

    # read magic bytes and reset filehandle
    my $old_layers = join '', map {":$_"} PerlIO::get_layers($fh);
    binmode($fh);
    read( $fh, my $magic_start, 3 );
    read( $fh, my $magic_end,   1 );
    binmode($fh,$old_layers); 
    seek($fh,0,0);

    # detect compression (must be BGZIP)
    if ($magic_start eq MAGIC_GZIP) {
        die "Gzip files must be compressed with bgzip for non-sequential access"
            if (ord($magic_end) != 0x04);
        require Compress::BGZF::Reader
            or die "Compress::BGZF::Reader not installed, no gzip support";
        close $fh;
        $fh = Compress::BGZF::Reader->new_filehandle($fn);
    }

    $self->{fh} = $fh;

    $self->_load_faidx;

    return $self;

}

sub write_index {
    
    my ($self, $fn) = @_;

    my $fn_idx  = $fn // $self->{fn} . '.fai';

    if (-e $fn_idx) {
        warn "Index file exists, won't overwrite\n";
        return 0;
    }

    warn "Creating index at $fn_idx\n";
    open my $idx, '>', $fn_idx or die "Error opening $fn_idx for writing: $!\n";

    my $fh = $self->{fh};

    my $curr_id;
    my $curr_len;
    my $curr_bases;
    my $curr_bytes;
    my $curr_offset;
    my $bl_mismatch = 0;
    my $ll_mismatch = 0;
    while (my $line =  <$fh>) {
        if ($line =~ /^>(\S+)/) {
            if (defined $curr_id) {
                say {$idx} join "\t",
                    $curr_id,
                    $curr_len,
                    $curr_offset,
                    $curr_bases,
                    $curr_bytes,
                ;
            }
            $curr_id = $1;
            $curr_offset = tell $fh;
            $curr_len = 0;
            $curr_bases = undef;
            $curr_bytes = undef;
            $bl_mismatch = 0;
            $ll_mismatch = 0;
        }
        elsif ($line =~ /^[A-Za-z\-]+(\r?\n?)$/) {
            die "Base length mismatch\n" if ($bl_mismatch);
            die "Line length mismatch\n" if ($ll_mismatch);
            my $ll  = length $line;
            my $bl  = $ll - length $1;
            $curr_len += $bl;
            $curr_bases //= $bl;
            $curr_bytes //= $ll;
            $bl_mismatch = 1 if ($bl != $curr_bases);
            $ll_mismatch = 1 if ($ll != $curr_bytes);
        }
        elsif ($line =~ /\S/) {
            die "Unexpected content: $line";
        }
                
    }

    # write remaining index
    if (defined $curr_id) {
        say {$idx} join "\t",
            $curr_id,
            $curr_len,
            $curr_offset,
            $curr_bases,
            $curr_bytes,
        ;
    }

    close $idx;
    return 1;

}
     

sub _load_faidx {
    
    my ($self) = @_;

    my $fn_idx  = $self->{fn} . '.fai';
    $self->write_index if (! -e $fn_idx);

    open my $in, '<', $fn_idx or die "Error opening index file: $!\n";
    while (my $line = <$in>) {
        chomp $line;
        my ($name, $len, $offset, $bases_per_line, $bytes_per_line)
            = split "\t", $line;
        die "ERROR: $fn_idx contains duplicate entries"
            if ( defined $self->{idx}->{$name} );
        my $eol = $bytes_per_line - $bases_per_line;
        $self->{idx}->{$name} = [$len, $offset, $bases_per_line, $eol];
    }
    close $in;

    return;

}

sub ids {

    my ($self) = @_;
    return keys %{ $self->{idx} };

}

sub length {

    my ($self, $id) = @_;
    return $self->{idx}->{$id}->[0];

}

sub fetch_seq {
    
    my ($self, $id, $start_bp, $end_bp) = @_;

    return undef if (! defined $self->{idx}->{$id});
    my ($len, $off, $bpl, $eol) = @{ $self->{idx}->{$id} };

    my $fh = $self->{fh};

    $start_bp = $start_bp // 1;
    $end_bp   = $end_bp   // $len;
    --$start_bp; #make 0-based
    die "Coordinates out of bounds" if ($start_bp < 0 || $end_bp > $len);
    my $l = $end_bp - $start_bp;

    seek $fh, $off + $start_bp + int(($start_bp)/$bpl)*$eol, 0;
    read($fh, my $seq, $l + int(($l+$start_bp%$bpl)/$bpl)*$eol);
    $seq =~ s/\s//g;

    ++$start_bp;

    my $desc;
    if ($start_bp > 1 || $end_bp < $len) {
        $desc = " ($start_bp-$end_bp)";
    }

    return BioX::Seq->new($seq, $id, $desc);

}


1;


__END__

=head1 NAME

BioX::Seq::Fetch - Fetch records from indexed FASTA non-sequentially

=head1 SYNOPSIS

    use BioX::Seq::Fetch;

    my $parser = BioX::Seq::Fetch->new($filename);

    my $seq = $parser->fetch('seq_ABC');
    my $sub = $parser->fetch('seq_XYZ', 8 => 15);

=head1 DESCRIPTION

C<BioX::Seq::Fetch> provides non-sequential access to records from indexed
sequence files. Currently only FASTA files indexed using C<samtoools faidx> or
another compatible method are supported.

=head1 METHODS

=over 4

=item B<new> I<FILENAME>

    my $parser = BioX::Seq::Fetch->new($filename);

Create a new C<BioX::Seq::Fetch> parser. Requires an input filename (STDIN or
open filehandles are not supported, as a filename is needed to find the
corresponding index file and to ensure than C<seek()>-ing is supported.

=item B<fetch_seq> I<SEQID> [I<START> I<END>]

Returns the requested sequence, or undef if no matching sequence is found.
Requires a valid sequence identifier and optionally 1-based start and end
coordinates to retrieve a substring (the entire sequence is returned by
default). A fatal error is thrown if the provided coordinates are outside the
range of [1-length(sequence)].

=back

=head1 COMPRESSION

C<BioX::Seq::Fetch> supports files compressed with blocked gzip (BGZIP),
typically using the C<bgzip> utility. This allows for pseudo-random access
without the need for full file decompression. The C<Compress::BGZIP> module is
required for this functionality.

=head1 INDEXING

Currently, this modules supports samtools-compatible index files. These are
index files typically generated by C<samtools faidx>. They should be named
identically to the FASTA file with the addition of a '.fai' suffix in order to
be found by this module. Support for this indexing scheme is provided due to
the prevalence of it's use. It has the downside of not supporting return of
any sequence descriptions, as only the offsets of the actual sequence bytes
are recorded.

=head1 CAVEATS AND BUGS

Please reports bugs to the author.

=head1 AUTHOR

Jeremy Volkening <jeremy *at* base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2014-2015 Jeremy Volkening

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

