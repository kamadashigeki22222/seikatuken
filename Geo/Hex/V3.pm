package Geo::Hex::V3;

use 5.008;
use warnings;
use strict;
use Carp ();

use POSIX qw/floor ceil/;
use Math::Round  ();
use Math::Trig   ();

our $VERSION = '0.01';
use vars qw(@ISA @EXPORT);
use Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(getZoneByLocation getZoneByCode);

use constant PI     => Math::Trig::pi();
use constant H_DEG  => PI * ( 30.0 / 180.0 );
use constant H_BASE => 20037508.34;
use constant H_K    => Math::Trig::tan( H_DEG );

my $i = 0;
my @h_key   = split//,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
my %h_key   = map { $_ => $i++ } @h_key;

$i = 0;
my @pow = map { 3 ** $_ } 0..17;

#
# APIs
#

sub latlng2geohex {
    return latlng2zone(@_)->{code};
}


sub geohex2latlng {
    my $zone = geohex2zone( $_[0] );
    return ( @{ $zone }{qw/lat lon level/} );
}


#
#
#

*getZoneByLocation = *latlng2zone;

sub latlng2zone {
    my ( $lat, $lon, $level ) = @_;
    $level += 2;

    my $h_size    = _hex_size( $level );

    my ( $lon_grid, $lat_grid ) = _loc2xy( $lat, $lon );
    my $unit_x    = 6.0 * $h_size;
    my $unit_y    = 6.0 * $h_size * H_K;
    my $h_pos_x   = ( $lon_grid + $lat_grid / H_K ) / $unit_x;
    my $h_pos_y   = ( $lat_grid - H_K * $lon_grid ) / $unit_y;
    my $h_x_0     = floor( $h_pos_x );
    my $h_y_0     = floor( $h_pos_y );
    my $h_x_q     = $h_pos_x - $h_x_0;
    my $h_y_q     = $h_pos_y - $h_y_0;
    my $h_x       = Math::Round::round( $h_pos_x );
    my $h_y       = Math::Round::round( $h_pos_y );

    if ($h_y_q > - $h_x_q + 1.0) {
        if ( ( $h_y_q < 2.0 * $h_x_q ) && ( $h_y_q > 0.5 * $h_x_q ) ) {
            $h_x = $h_x_0 + 1.0;
            $h_y = $h_y_0 + 1.0;
        }
    } 
    elsif ( $h_y_q < - $h_x_q + 1.0 ) {
        if ( ( $h_y_q > ( 2.0 * $h_x_q ) - 1.0 ) && ( $h_y_q < ( 0.5 * $h_x_q ) + 0.5 ) ) {
            $h_x = $h_x_0;
            $h_y = $h_y_0;
        }
    }

    my $h_lat = ( H_K * $h_x * $unit_x + $h_y * $unit_y ) / 2;
    my $h_lon = ( $h_lat - $h_y * $unit_y ) / H_K;

    my ( $z_loc_y, $z_loc_x ) = _xy2loc( $h_lon, $h_lat );

    if ( H_BASE - $h_lon < $h_size ) {
        $z_loc_x  = 180;
        ( $h_x, $h_y ) = ( $h_y, $h_x );
    }

    my $h_code  = "";
    my @code3_x = ();
    my @code3_y = ();
    my $mod_x   = $h_x;
    my $mod_y   = $h_y;

    for my $i ( 0 .. $level ) {
        my $h_pow    = $pow[ $level - $i ];
        my $half_pow = ceil( $h_pow / 2 );

        if ( $mod_x >= $half_pow ) {
            $code3_x[$i] = 2;
            $mod_x -= $h_pow;
        }
        elsif ( $mod_x <= - $half_pow ) {
            $code3_x[$i] = 0;
            $mod_x += $h_pow;
        }
        else {
            $code3_x[$i] = 1;
        }

        if ( $mod_y >= $half_pow ) {
            $code3_y[$i] = 2;
            $mod_y -= $h_pow;
        }
        elsif ( $mod_y <= - $half_pow ) {
            $code3_y[$i] = 0;
            $mod_y += $h_pow;
        }
        else {
            $code3_y[$i] = 1;
        }
    }

    # ternary to nonary
    for ( 0 .. $#code3_x ) {
        $h_code .= _from_base( $code3_x[$_] . $code3_y[$_] );
    }

    # three head chars are converted into trigesimal number
    my $head3 = substr( $h_code, 0, 3 );
    my $code  = $h_key[ int( $head3 / 30.0 ) ] . $h_key[ $head3 % 30 ] . substr( $h_code, 3 );

    Geo::Hex::Zone::V3->new({
        code  => $code,
        level => $level - 2,
        x     => $h_x,
        y     => $h_y,
        lat   => $z_loc_y,
        lon   => $z_loc_x
   });
}


*getZoneByCode = *geohex2zone;

sub geohex2zone {
    my $code    = shift;
    my $level   = length($code);
    my $h_size  = _hex_size($level);
    my $unit_x  = 6.0 * $h_size;
    my $unit_y  = 6.0 * $h_size * H_K;
    my $h_x     = 0.0;
    my $h_y     = 0.0;
    my $h_dec9  = ( $h_key{ substr($code, 0, 1) } * 30.0 + $h_key{ substr($code, 1, 1) } ) . substr($code, 2);

    # TODO: comment
    if ( $h_dec9 =~ /^([15])[^125][^125]/ ) {
        $h_dec9 = ($1 eq '5' ? '7' : '3') . substr($h_dec9, 1);
    }

    my $d9xlen = length($h_dec9);
    for (my $i = 0; $i < $level + 1 - $d9xlen; $i++) {
        $h_dec9 = 0 . $h_dec9;
        $d9xlen++;
    }

    my $h_dec3 = "";
    for my $i ( 0 .. $d9xlen - 1 ) {
        my $h_dec0 = _to_base( substr($h_dec9, $i, 1) );

        unless ( defined $h_dec0 ) {
            $h_dec3 .= '00';
        }
        elsif ( length($h_dec0) == 1 ) {
            $h_dec3 .= '0';
        }

        $h_dec3 .= $h_dec0;
    }

    my @h_decx = ();
    my @h_decy = ();

    for my $i ( 0 .. int( length( $h_dec3 ) / 2 ) -1 ) {
        $h_decx[$i] = substr( $h_dec3, $i * 2, 1 );
        $h_decy[$i] = substr( $h_dec3, $i * 2 + 1, 1 );
    }

    foreach my $i ( 0..$level ) {
        my $h_pow = 3 ** ($level - $i);
        if ( $h_decx[$i] eq '0' ) {
            $h_x -= $h_pow;
        } elsif ( $h_decx[$i] eq '2' ) {
            $h_x += $h_pow;
        }
        if ( $h_decy[$i] eq '0' ) {
            $h_y -= $h_pow;
        } elsif ( $h_decy[$i] eq '2' ) {
            $h_y += $h_pow;
        }
    }

    my $h_lat_y = ( H_K * $h_x * $unit_x + $h_y * $unit_y ) / 2;
    my $h_lon_x = ( $h_lat_y - $h_y * $unit_y ) / H_K;

    my ( $h_loc_lat, $h_loc_lon ) = _xy2loc( $h_lon_x, $h_lat_y );

    # a bad hack for a difference between internal NV and IV.
    if ( $h_loc_lon > 180 or $h_loc_lon eq '180' ) {
        my $c = 3 ** $level;
        $h_x -= $c;
        $h_y += $c;
    }

    if ( $h_loc_lon > 180 ) {
        $h_loc_lon -= 360;
    }
    elsif ( $h_loc_lon < -180 ) {
        $h_loc_lon += 360;
    }

    Geo::Hex::Zone::V3->new({
        x     => $h_x,
        y     => $h_y,
        lat   => $h_loc_lat,
        lon   => $h_loc_lon,
        code  => $code,
        level => length($code) - 2,
    });
}


# copied and modified from Math::BaseCalc
sub _from_base {
    my $str = $_[0];
    my $dignum = 3;

    $str = reverse $str;
    my $result = 0;
    while (length $str) {
        # For large numbers, force result to be an integer (not a float)
        $result = int( $result * $dignum + chop( $str ) );
    }

    return $result;
}

# copied and modified from Math::BaseCalc
sub _to_base {
    my ($num) = @_;
    my $dignum = 3;# @{$self->{digits}};

    my $result = '';

    while ($num>0) {
        substr($result,0,0) = $num % $dignum;
        $num = int ($num/$dignum);
    }

    return length $result ? $result : 0;
}

sub _hex_size {
  my $hex = H_BASE / 3.0 ** ( $_[0] + 1 );
  return H_BASE / 3.0 ** ( $_[0] + 1 );
}

sub _loc2xy {
    my ($lat, $lon) = @_;
    my $x = $lon * H_BASE / 180;
    my $y = log( Math::Trig::tan( ( 90 + $lat ) * PI / 360 ) ) / ( PI / 180 );
    $y *= H_BASE / 180;
    return ( $x, $y );
}

sub _xy2loc {
    my ( $x, $y ) = @_;
    my $lon = 180 * ($x / H_BASE);
    my $lat = 180 * ($y / H_BASE);
    $lat = 180 / PI * ( 2 * Math::Trig::atan( exp( $lat * PI / 180 ) ) - PI / 2 );
    return ( $lat, $lon );
}



package
    Geo::Hex::Zone::V3;

use Geo::Hex::Zone;
our @ISA = 'Geo::Hex::Zone';

use constant H_DEG => Math::Trig::tan( Math::Trig::pi * 60 / 180 );

sub spec_version { 3; }

sub hex_size {
    return exists $_[0]->{ _cache_hex_size }
                ? $_[0]->{ _cache_hex_size }
                : $_[0]->{ _cache_hex_size } = Geo::Hex::V3::_hex_size( $_[0]->level + 2 );
}

sub hex_coords {
    my ( $lat, $lon ) = ( $_[0]->lat, $_[0]->lon );
    my ( $h_x, $h_y ) = Geo::Hex::V3::_loc2xy( $lat, $lon );
    my $hex_size      = $_[0]->hex_size;

    my $top    = ( Geo::Hex::V3::_xy2loc( $h_x, $h_y + H_DEG * $hex_size ) )[0];
    my $bottom = ( Geo::Hex::V3::_xy2loc( $h_x, $h_y - H_DEG * $hex_size ) )[0];

    my $left   = ( Geo::Hex::V3::_xy2loc( $h_x - 2 * $hex_size, $h_y ) )[1];
    my $right  = ( Geo::Hex::V3::_xy2loc( $h_x + 2 * $hex_size, $h_y ) )[1];

    my $cleft  = ( Geo::Hex::V3::_xy2loc( $h_x - 1 * $hex_size, $h_y ) )[1];
    my $cright = ( Geo::Hex::V3::_xy2loc( $h_x + 1 * $hex_size, $h_y ) )[1];

    return [
        [ $lat, $left ],
        [ $top, $cleft ],
        [ $top, $cright ],
        [ $lat, $right ],
        [ $bottom, $cright ],
        [ $bottom, $cleft ],
    ];
}


1;
__END__

=pod

=head1 NAME

Geo::Hex::V3 - GeoHex vresion 3

=head1 DESCRIPTION

GeoHex v3 encoder/decoder

=head1 SEE ALSO

L<http://geogames.net/geohex/v3>

=head1 AUTHOR

soh335

=head1 COPYRIGHT AND LICENSE

GeoHex by @sa2da (http://geogames.net) is licensed under
Creative Commons BY-SA 2.1 Japan License.

Geo::Hex::V3 Copyright (c) 2011 by soh335

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

