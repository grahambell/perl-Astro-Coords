#!perl

# This script tests that the coordinates are reversible
use strict;
use Test::More tests => 24;
use Time::Piece qw/ :override /;

require_ok('Astro::Coords');
require_ok('Astro::Telescope');
require_ok('Astro::SLA');

my %test = (
	    equatorial => {
			   name => '0221+067',
			   ra   => '02 24 28.428',
			   dec  => '+06 59 23.34',
			   type => 'J2000',
			  },
	    planet      => { 
			    planet => 'mars' 
			   },
	    elements    => { 
			    elements => {
					 # Original
					 EPOCH => '1997 Apr 1.1373',
					 ORBINC => 89.4300* &Astro::SLA::DD2R,
					 ANODE =>  282.4707* &Astro::SLA::DD2R,
					 PERIH =>  130.5887* &Astro::SLA::DD2R,
					 AORQ => 0.914142,
					 E => 0.995068,
					}
			   },
	   );

# telescope
my $tel = new Astro::Telescope( 'JCMT' );

# reference time
my $date = gmtime;

for my $chash (keys %test) {

  # Create a new coordinate object
  my $c = new Astro::Coords( %{ $test{$chash} } );
  ok($c, "instantiate object $chash");
  $c->datetime( $date );
  $c->telescope( $tel );

  #print $c->status;

  # now instantiate an AZEL object
  my $azel = new Astro::Coords( az => $c->az, el => $c->el,
				units => 'radians');

  $azel->datetime( $date );
  $azel->telescope( $c->telescope );

  #print $azel->status;

  # compare
  my $fmt = '%.5g';
  for my $type (qw/ az el ra_app dec_app ha _lst /) {
    is(sprintf($fmt,$azel->$type), sprintf($fmt,$c->$type),
       "compare $type");
  }

}