package Astro::Coords;

=head1 NAME

Astro::Coords - Class for handling astronomical coordinates

=head1 SYNOPSIS

  use Astro::Coords;

  $c = new Astro::Coords( ra   => '05:22:56',
                          dec  => '-26:20:40.4',
                          type => 'B1950'
                          units=> 'sexagesimal');

  $c = new Astro::Coords( long => '05:22:56',
                          lat  => '-26:20:40.4',
                          type => 'galactic');

  $c = new Astro::Coords( planet => 'mars' );

  $c = new Astro::Coords( elements => \%elements );

  $c = new Astro::Coords( az => 345, el => 45 );

  # Return FK5 J2000 coordinates in radians
  ($ra, $dec) = $c->fk5();

  # in degrees or as sexagesimal string or arrays
  ($ra, $dec) = $c->fk5( "DEG" );
  ($ra, $dec) = $c->fk5( "STRING" );
  ($raref, $decref) = $c->fk5( "ARRAY" );

  # in galactic coordinates
  ($long, $lat) = $c->gal;

  # Specify a telescope
  $c->telescope( 'JCMT' );

  # Determine apparent RA/Dec for the current time and telescope
  ($appra, $appdec) = $c->apparent;

  # and az el
  ($az, $el) = $c->azel;

  # and ha, dec
  ($ha, $dec) = $c->hadec;

  # obtain summary string of object
  $summary = "$c";

  # Obtain full summary as an array
  @summary = $c->array;

  # See if the target is observable for the current time
  # and telescope
  $obs = 1 if $c->isObservable;

  # Calculate distance to another coordinate (in radians)
  $distance = $c->distance( $c2 ); # not yet supported


=head1 DESCRIPTION

Class for manipulating and transforming astronomical coordinates.
All fixed sky coordinates are converted to FK5 J2000 internally.

For time dependent calculations a telescope location and reference
time must be provided.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = '0.02';

use Astro::SLA ();
use Astro::Coords::Equatorial;
use Astro::Coords::Elements;
use Astro::Coords::Planet;
use Astro::Coords::Fixed;
use Astro::Coords::Calibration;

use Time::Piece  '1.00'; # override gmtime

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

This can be treated as an object factory. The object returned
by this constructor depends on the arguments supplied to it.
Coordinates can be provided as orbital elements, a planet name
or an equatorial (or related) fixed coordinate specification (e.g.
right ascension and declination).

A complete (for some definition of complete) specification for
the coordinates in question must be provided to the constructor.
The coordinates given as arguments will be converted to an internal
format.

A planet name can be specified with:

  $c = new Astro::Coords( planet => "sun" );

Orbital elements as:

  $c = new Astro::Coords( elements => \%elements );

where C<%elements> must contain the names of the elements
as used in the SLALIB routine slaPlante.

Fixed astronomical oordinate frames can be specified using:

  $c = new Astro::Coords( ra => 
                          dec =>
			  long =>
			  lat =>
			  type =>
			  units =>
			);

C<ra> and C<dec> are used for HMSDeg systems (eg type=J2000). Long and
Lat are used for degdeg systems (eg where type=galactic). C<type> can
be "galactic", "j2000", "b1950", and "supergalactic".
The C<units> can be specified as "sexagesimal" (when using colon or
space-separated strings), "degrees" or "radians". The default is
determined from context.

Fixed (as in fixed on Earth) coordinate frames can be specified
using:

  $c = new Astro::Coords( dec =>
                          ha =>
                          tel =>
                          az =>
                          el =>
                          units =>
                        );

where C<az> and C<el> are the Azimuth and Elevation. Hour Angle
and Declination require a telescope. Units are as defined above.

Finally, if no arguments are given the object is assumed
to be of type C<Astro::Coords::Calibration>.

Returns C<undef> if an object could not be created.

=cut

sub new {
  my $class = shift;

  my %args = @_;

  my $obj;

  # Always try for a planet object first if $args{planet} is used
  # (it might be that ra/dec are being specified and planet is a target
  # name - this allows all the keys to be specified at once and the
  # object can decide the most likely coordinate object to use
  # This has the distinct disadvantage that planet is always tried
  # even though it is rare. We want to be able to throw anything
  # at this without knowing what we are.
  if (exists $args{planet} and defined $args{planet}) {
    $obj = new Astro::Coords::Planet( $args{planet} );
  }

  # planet did not work. Try something else.
  unless (defined $obj) {

    # For elements we must not only check for the elements key
    # but also make sure that that key points to a hash containing
    # at least the EPOCH key
    if (exists $args{elements} and defined $args{elements}
       and UNIVERSAL::isa($args{elements},"HASH") 
       and exists $args{elements}{EPOCH}
       and defined $args{elements}{EPOCH}) {

      $obj = new Astro::Coords::Elements( $args{planet} );

    } elsif (exists $args{type} and defined $args{type}) {

      $obj = new Astro::Coords::Equatorial( %args );

    } elsif (exists $args{az} or exists $args{el} or exists $args{ha}) {

      $obj = new Astro::Coords::Fixed( %args );

    } elsif ( scalar keys %args == 0 ) {

      $obj = new Astro::Coords::Calibration();

    } else {
    # unable to work out what you are asking for
      return undef;

    }
  }

  return $obj;
}


=back

=head2 Accessor Methods

=over 4


=item B<telescope>

Telescope object (an instance of Astro::Telescope) to use
for obtaining the position of the telescope to use for
the determination of source elevation.

  $c->telescope( new Astro::Telescope( 'JCMT' ));
  $tel = $c->telescope;

This method checks that the argument is of the correct type.

=cut

sub telescope {
  my $self = shift;
  if (@_) { 
    my $tel = shift;
    return undef unless UNIVERSAL::isa($tel, "Astro::Telescope");
    $self->{Telescope} = $tel;
  }
  return $self->{Telescope};
}


=item B<datetime>

Date/Time object to use when determining the source elevation.

  $c->datetime( new Time::Piece() );

Argument must be of type C<Time::Piece> (or C<Time::Object> version
1.00). The method dies if this is not the case [it must support an
C<mjd> method].

If no argument is specified an object referring to the current time
(GMT/UT) is returned.

=cut

sub datetime {
  my $self = shift;
  if (@_) {
    my $time = shift;
    croak "Argument does not have an mjd() method"
      unless (UNIVERSAL::can($time, "mjd"));
    $self->{DateTime} = $time;
  }
  return (defined $self->{DateTime} ? $self->{DateTime} : gmtime );
}

=back

=head2 General Methods

=over 4

=item B<ra_app>

Apparent RA for the current time. Arguments are similar to those
specified for "dec".

  $ra_app = $c->ra_app( format => "s" );

=cut

sub ra_app {
  my $self = shift;
  my %opt = @_;
  $opt{format} = "radians" unless defined $opt{format};
  my $ra = ($self->_apparent)[0];
  # Convert to hours if we are using a string or hour format
  $ra = $self->_cvt_tohrs( \$opt{format}, $ra);
  return $self->_cvt_fromrad( $ra, $opt{format});
}


=item B<dec_app>

Apparent Dec for the currently stored time. Arguments are similar to those
specified for "dec".

  $dec_app = $c->dec_app( format => "s" );

=cut

sub dec_app {
  my $self = shift;
  my %opt = @_;
  $opt{format} = "radians" unless defined $opt{format};
  return $self->_cvt_fromrad( ($self->_apparent)[1], $opt{format});
}

=item B<ha>

Get the hour angle for the currently stored LST. Default units are in
radians.

  $ha = $c->ha;
  $ha = $c->ha( format => "deg" );

=cut

sub ha {
  my $self = shift;
  my %opt = @_;
  $opt{format} = "radians" unless defined $opt{format};
  my $ha = $self->_lst - $self->ra_app;
  # Convert to hours if we are using a string or hour format
  $ha = $self->_cvt_tohrs( \$opt{format}, $ha);
  return $self->_cvt_fromrad( $ha, $opt{format});
}

=item B<az>

Azimuth of the source for the currently stored time at the current
telescope. Arguments are similar to those specified for "dec".

  $az = $c->az();

If no telescope is defined the equator is used.

=cut

sub az {
  my $self = shift;
  my %opt = @_;
  $opt{format} = "radians" unless defined $opt{format};
  return $self->_cvt_fromrad( ($self->_azel)[0], $opt{format});
}

=item B<el>

Elevation of the source for the currently stored time at the current
telescope. Arguments are similar to those specified for "dec".

  $el = $c->el();

If no telescope is defined the equator is used.

=cut

sub el {
  my $self = shift;
  my %opt = @_;
  $opt{format} = "radians" unless defined $opt{format};
  return $self->_cvt_fromrad( ($self->_azel)[1], $opt{format});
}

=item B<pa>

Parallactic angle of the source for the currently stored time at the
current telescope. Arguments are similar to those specified for "dec".

  $pa = $c->pa();

If no telescope is defined the equator is used.

=cut

sub pa {
  my $self = shift;
  my %opt = @_;
  $opt{format} = "radians" unless defined $opt{format};
  my $ha = $self->ha;
  my $dec = $self->dec_app;
  my $tel = $self->telescope;
  my $lat = ( defined $tel ? $tel->lat : 0.0);
  return $self->_cvt_fromrad(Astro::SLA::slaPa($ha, $dec, $lat), $opt{format});
}

=item B<isObservable>

Determine whether the coordinates are accessible for the current
time and telescope.

  $isobs = $c->isObservable;

Returns false if a telescope has not been specified (see
the C<telescope> method) or if the specified telescope does not
know its own limits.

=cut

sub isObservable {
  my $self = shift;

  # Get the telescope
  my $tel = $self->telescope;
  return 0 unless defined $tel;

  # Get the limits hash
  my %limits = $tel->limits;

  if (exists $limits{type}) {

    if ($limits{type} eq 'AZEL') {

      # Get the current elevation of the source
      my $el = $self->el;

      if ($el > $limits{el}{min} and $el < $limits{el}{max}) {
	return 1;
      } else {
	return 0;
      }

    } elsif ($limits{type} eq 'HADEC') {

      # Get the current HA
      my $ha = $self->ha;

      # Normalize to +/-pi
      $ha = Astro::SLA::slaDrange( $ha );


      if ( $ha > $limits{ha}{min} and $ha < $limits{ha}{max}) {
	my $dec= $self->dec_app;

	if ($dec > $limits{dec}{min} and $dec < $limits{dec}{max}) {
	  return 1;
	} else {
	  return 0;
	}

      } else {
	return 0;
      }

    } else {
      # have no idea
      return 0;
    }

  } else {
    return 0;
  }

}


=item B<array>

Return a summary of this object in the form of an array containing
the following:

  coordinate type (eg PLANET, RADEC, MARS)
  ra2000          (J2000 RA in radians [for equatorial])
  dec2000         (J2000 dec in radians [for equatorial])
  elements        (up to 8 orbital elements)

=cut

sub array {
  my $self = shift;
  croak "The method array() must be subclassed\n";
}

=item B<status>

Return a status string describing the current coordinates.
This consists of the current elevation, azimuth, hour angle
and declination. If a telescope is defined the observability
of the target is included.

=cut

sub status {
  my $self = shift;
  my $string;

  $string .= "Coordinate type:" . $self->type ."\n";

  $string .= "Elevation:      " . $self->el(format=>'d')." deg\n";
  $string .= "Azimuth  :      " . $self->az(format=>'d')." deg\n";
  my $ha = Astro::SLA::slaDrange( $self->ha ) * Astro::SLA::DR2H;
  $string .= "Hour angle:     " . $ha ." hrs\n";
  $string .= "Apparent dec:   " . $self->dec_app(format=>'d')." deg\n";

  if (defined $self->telescope) {
    $string .= "Telescope:      " . $self->telescope->fullname . "\n";
    if ($self->isObservable) {
      $string .= "The target is currently observable\n";
    } else {
      $string .= "The target is not currently observable\n";
    }
  }

  $string .= "For time ". $self->datetime ."\n";

  return $string;
}


=item B<_lst>

Calculate the LST for the current date/time and
telescope and return it (in radians).

If no date/time is specified the current time will be used.
If no telescope is defined the LST will be from Greenwich.

This is labelled as an internal routine since it is not clear whether
the method to determine LST should be here or simply placed into
C<Time::Object>. In practice this simply calls the
C<Astro::SLA::ut2lst> function with the correct args (and therefore
does not need the MJD). It will need the longitude though so we
calculate it here.

=cut

sub _lst {
  my $self = shift;
  my $time = $self->datetime;
  my $tel = $self->telescope;

  # Get the longitude (in radians)
  my $long = (defined $tel ? $tel->long : 0.0 );

  # Return the first arg
  return (Astro::SLA::ut2lst( $time->year, $time->mon,
			      $time->mday, $time->hour,
			      $time->min, $time->sec, $long))[0];

}

=item B<_azel>

Return Azimuth and elevation for the currently stored time and telescope.
If no telescope is present the equator is used.

=cut

sub _azel {
  my $self = shift;
  my $ha = $self->ha;
  my $dec = $self->dec_app;
  my $tel = $self->telescope;
  my $lat = ( defined $tel ? $tel->lat : 0.0);
  Astro::SLA::slaDe2h( $ha, $dec, $lat, my $az, my $el );
  return ($az, $el);
}

=back

=head2 Private Methods

=over 4

=item B<_cvt_tohrs>

Scale a value in radians such that it can be translated
correctly to hours by routines that are assuming output is
required in degrees (effectively dividing by 15).

  $radhr = $c->_cvt_tohrs( \$format, $rad );

Format is modified to reflect the change expected by
C<_cvt_fromrad()>. 

=cut

sub _cvt_tohrs {
  my $self = shift;
  my ($fmt, $rad) = @_;
  # Convert to hours if we are using a string or hour format
  $rad /= 15.0 if $$fmt =~ /^[ash]/;
  # and reset format to use degrees
  $$fmt = "degrees" if $$fmt =~ /^h/;
  return $rad;
}

=item B<_cvt_fromrad>

Convert the supplied value (in radians) to the desired output
format. Output options are:

 sexagesimal - A string of format either dd:mm:ss
 radians     - The default (no change)
 degrees     - decimal degrees
 array       - return a reference to an array containing the
               sign/degrees/minutes/seconds

If the output is required in hours, pre-divide the radians by 15.0
prior to calling this routine.

  $out = $c->_cvt_fromrad( $rad, $format );

=cut

sub _cvt_fromrad {
  my $self = shift;
  my $in = shift;
  my $format = shift;
  $format = '' unless defined $format;

  if ($format =~ /^d/) {
    $in *= Astro::SLA::DR2D;
  } elsif ($format =~ /^[as]/) {
    my @dmsf;
    Astro::SLA::slaDr2af(2, $in, my $sign, @dmsf);
    if ($format =~ /^a/) {
      # Store the sign
      unshift(@dmsf, $sign);
      # Combine the fraction
      my $frac = pop(@dmsf);
      $dmsf[-1] .= ".$frac";
      # Store the reference
      $in = \@dmsf;
    } else {
      $sign = '' if $sign eq "+";
      $in = $sign . join(":",@dmsf[0..2]) . ".$dmsf[3]";
    }
  }

  return $in;
}

=item B<_cvt_torad>

Convert from the supplied units to radians. The following
units are supported:

 sexagesimal - A string of format either dd:mm:ss or "dd mm ss"
 degrees     - decimal degrees
 radians     - radians
 hours       - decimal hours

If units are not supplied (undef) default is to assume "sexagesimal"
if the supplied string contains spaces or colons, "degrees" if the
supplied number is greater than 2*PI (6.28), and "radians" for all
other values.

  $radians = Astro::Coords::Equatorial->_cvt_torad("sexagesimal",
                                                   "5:22:63")

An optional final argument can be used to indicate that the supplied
string is in hours rather than degrees. This is only used when
units is set to "sexagesimal".

Returns undef on error.

=cut

# probably need to use a hash argument

sub _cvt_torad {
  my $self = shift;
  my $units = shift;
  my $input = shift;
  my $hms = shift;

  return undef unless defined $input;

  # Clean up the string
  $input =~ s/^\s+//g;
  $input =~ s/\s+$//g;

  # guess the units
  unless (defined $units) {

    # Now if we have a space or : then we have a real string
    if ($input =~ /(:|\s)/) {
      $units = "sexagesimal";
    } elsif ($input > Astro::SLA::D2PI) {
      $units = "degrees";
    } else {
      $units = "radians";
    }

  }

  # Now process the input - starting with strings
  my $output;
  if ($units =~ /^s/) {

    # Need to clean up the string for slalib
    $input =~ s/:/ /g;

    my $nstrt = 1;
    Astro::SLA::slaDafin( $input, $nstrt, $output, my $j);
    $output = undef unless $j == 0;

    # If we were in hours we need to multiply by 15
    $output *= 15.0 if $hms;

  } elsif ($units =~ /^h/) {
    # Hours in decimal
    $output = $input * Astro::SLA::DH2R;

  } elsif ($units =~ /^d/) {
    # Degrees decimal
    $output = $input * Astro::SLA::DD2R;

  } else {
    # Already in radians
    $output = $input;
  }

  return $output;
}

=back

=head1 REQUIREMENTS

C<Astro::SLA> is used for all internal astrometric calculations.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

