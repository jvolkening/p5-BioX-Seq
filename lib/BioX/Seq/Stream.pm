package BioX::Seq::Stream;

use 5.012;
use strict;
use warnings;

use File::Which;
use Scalar::Util qw/openhandle/;
use BioX::Seq;
use POSIX qw/ceil/;
use Cwd qw/abs_path/;
use File::Basename qw/fileparse/;
use Scalar::Util qw/blessed/;

# define or search for binary locations
# if these are not available
our $GZIP_BIN = which('pigz')   // which('gzip');
our $BZIP_BIN = which('pbzip2') // which('bzip2');
our $DSRC_BIN = which('dsrc2')  // which('dsrc');
our $FQZC_BIN = which('fqz_comp');

use constant MAGIC_GZIP => pack('C3', 0x1f, 0x8b, 0x08);
use constant MAGIC_DSRC => pack('C2', 0xaa, 0x02);
use constant MAGIC_BZIP => 'BZh';
use constant MAGIC_FQZC => '.fqz';
use constant MAGIC_BAM  => pack('C4', 0x42, 0x41, 0x4d, 0x01);
use constant MAGIC_2BIT => pack('C4', 0x1a, 0x41, 0x27, 0x43);

sub new {

    my ($class,$fn) = @_;

    my $self = bless {} => $class;

    if (defined $fn) {

        my $fh = openhandle($fn); # can pass filehandle too;
        if (! defined $fh) { # otherwise assume filename
            
            #if passed a filename, try to determine if compressed
            open $fh, '<', $fn or die "Error opening $fn for reading\n";

            #read first four bytes as raw
            my $old_layers = join '', map {":$_"} PerlIO::get_layers($fh);
            binmode($fh);
            read( $fh, my $magic, 4 );
            binmode($fh, $old_layers); 

            #check for compression and open stream if found
            if (substr($magic,0,3) eq MAGIC_GZIP) {
                close $fh;
                if (! defined $GZIP_BIN) {
                    # fall back on Perl-based method (but can be SLOOOOOW!)
                    require IO::Uncompress::Gunzip;
                    $fh = IO::Uncompress::Gunzip->new($fn, MultiStream => 1);
                }
                else {
                    open  $fh, '-|', "$GZIP_BIN -dc $fn"
                        or die "Error opening gzip stream: $!\n";
                }
            }
            elsif (substr($magic,0,3) eq MAGIC_BZIP) {
                close $fh;
                if (! defined $BZIP_BIN) {
                    # fall back on Perl-based method (but can be SLOOOOOW!)
                    require IO::Uncompress::Bunzip2;
                    $fh = IO::Uncompress::Bunzip2->new($fn, MultiStream => 1);
                }
                else {
                    open $fh, '-|', "$BZIP_BIN -dc $fn"
                        or die "Error opening bzip2 stream: $!\n";
                }
            }
            elsif (substr($magic,0,2) eq MAGIC_DSRC) {
                die "no dsrc backend found\n" if (! defined $DSRC_BIN);
                close $fh;
                open $fh, '-|', "$DSRC_BIN d -s $fn"
                    or die "Error opening dsrc stream: $!\n";
            }
            elsif (substr($magic,0,4) eq MAGIC_FQZC) {
                die "no fqz backend found\n" if (! defined $FQZC_BIN);
                close $fh;
                open $fh, '-|', "$FQZC_BIN -d $fn"
                    or die "Error opening fqz_comp stream: $!\n";
            }
            else {
                seek($fh,0,0);
            }

        }
        $self->{fh} = $fh;

    }
    else {
        $self->{fh} = \*STDIN;
    }

    # handle files coming from different platforms
    #my @layers = PerlIO::get_layers($self->{fh});
    #binmode($self->{fh},':unix:stdio:crlf');

    $self->_guess_format;

    # detect line endings for text files based on first line
    # (other solutions, such as using the :crlf layer or s///
    # instead of chomp may be marginally more robust but slow
    # things down too much)

    if ($self->{buffer} =~ /([\r\n]{1,2})$/) {
        $/ = $1;
    }

    $self->_init;

    return $self;

}

sub _guess_format {

    my ($self) = @_;

    # Filetype guessing must be based on first two bytes (or less)
    # which are stored in an object buffer
    my $r = (read $self->{fh}, $self->{buffer}, 2);
    die "failed to read intial bytes" if ($r != 2);

    my $search_path = abs_path(__FILE__);
    $search_path =~ s/\.pm$//i;
    my @matched;
    for my $module ( glob "$search_path/*.pm" ) {
        my ($name,$path,$suff) = fileparse($module, qr/\.pm/i);
        my $classname = blessed($self) . "::$name";
        eval "require $classname";
        if ($classname->_check_type($self)) {
            push @matched, $classname;
        }
    }

    die "Failed to guess filetype\n"   if (scalar(@matched) < 1);
    die "Multiple filetypes matched\n" if (scalar(@matched) > 1);

    eval "require $matched[0]";
    bless $self => $matched[0];

}


1;


__END__

=head1 NAME

BioX::Seq::Stream - Parse FASTA and FASTQ files sequentially

=head1 SYNOPSIS

    use BioX::Seq::Stream;

    my $parser = BioX::Seq::Stream->new; #defaults to STDIN
    my $parser = BioX::Seq::Stream->new( $filename );
    my $parser = BioX::Seq::Stream->new( $filehandle );

    while (my $seq = $parser->next_seq) {

        # $seq is a BioX::Seq object

    }

=head1 DESCRIPTION

C<BioX::Seq::Stream> is a sequential parser for FASTA and FASTQ files. It
should handle any valid input, with the exception of the use of semi-colons to
indicate FASTA comments (this could be easily implemented, but I have never
seen an actual FASTA file like this in the wild, and the NCBI FASTA
specification does not allow for this usage). In particular, it will properly
handle FASTQ files with multi-line (wrapped) sequence and quality strings. I
have never seen a FASTQ file like this either, but apparently this is
technically valid and a few software programs will still create files like
this.

=head1 METHODS

=over 4

=item B<new>

=item B<new> I<FILENAME>

=item B<new> I<FILEHANDLE>

    my $parser = BioX::Seq::Stream->new();

Create a new C<BioX::Seq::Stream> parser. If no arguments are given (or if the
argument given has an undefined value), the parser will read from STDIN.
Otherwise, the parser will determine whether a filename or a filehandle is
provided and act accordingly. Returns a C<BioX::Seq::Stream> parser object.

=item B<next_seq>

    my $seq = $parser->next_seq();

Reads the next sequence from the filehandle. Returns a C<BioX::Seq> object, or
I<undef> if the end of the file is reached.

The first time this is called, the parser will try to determined whether the
input is FASTA or FASTQ based on the first character in the file - should
always be ">" for FASTA and "@" for FASTQ.

=back

=head1 DECOMPRESSION

If a filename is passed to the constructor, the module will read the first
four bytes and match against known file compression magic bytes. If a
compressed file is suspected, and a compatible decompression program can be
found using L<File::Which>, a piped filehandle is opened for reading.
Currently the following formats are supported (if appropriate binaries are
found):

  * GZIP

  * BZIP2

  * DSRC v2

  * FQZCOMP

Benchmarking indicated a fairly significant speed difference in handling
decompression using external binaries vs. Perl modules, so the current
implementation uses the former for decompressing on-the-fly. This may require
additional work to compile to proper binaries for a given platform. This
module will try to find the location of the proper binaries by their typical
name. If installed using a non-standard name, the following package variables
can be set:

=over 4

=item $BioX::Seq::Stream::GZIP_BIN

By default, looks for a binary in PATH named 'pigz' or 'gzip'

=item $BioX::Seq::Stream::BZIP_BIN

By default, looks for a binary in PATH named 'pbzip2' or 'bzip2'

=item $BioX::Seq::Stream::DSRC_BIN

By default, looks for a binary in PATH named 'dsrc2' or 'dsrc'

=item $BioX::Seq::Stream::FQZC_BIN

By default, looks for a binary in PATH named 'fqz_comp'

=back

=head1 CAVEATS AND BUGS

Minimal input validation is performed. FASTQ ID lines are checked for proper
format and sequence and quality lengths are compared, but the contents of
sequence and quality strings are not sanity-checked, nor is the FASTA sequence
string.

Please reports bugs to the author.

=head1 AUTHOR

Jeremy Volkening <jeremy *at* base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2014-2016 Jeremy Volkening

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
