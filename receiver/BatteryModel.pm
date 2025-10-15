#!/usr/bin/perl
package BatteryModel;
use strict;
use warnings;
use DBI;
use Logger::Syslog;
#use Data::Dumper;

use Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK);
@ISA    = qw(Exporter);
@EXPORT = qw(closeBattDatabase openBattDatabase getBatteryDetails
	     getLevelAsVoltage setBatteryVoltage
);

@EXPORT_OK = qw();

# Database handle used by all functions
my $dbfile = "/home/wkt/Tanks/batteries.db";
my $dbh;

# Close the database
sub closeBattDatabase {
    $dbh->disconnect;
    undef($dbh);
}

# Open the database
sub openBattDatabase {
    my ($dfile) = @_;
    $dbfile = $dfile if ($dfile);

    if ( !defined($dbh) ) {
        $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", "", "" );
    }
}

# Get details of one battery
sub getBatteryDetails {
    my $id = shift;
    my @row =
      $dbh->selectrow_array( "SELECT * FROM battery WHERE id = ?", undef, $id );
    return (@row);
}

# Given a raw ADC measurement, the ADC value at 0V, a reference voltage
# and the ADC measurement at that voltage, calculate and return the voltage
# from the raw ADC measurement. Change negative values to 0V.
sub getLevelAsVoltage {
    my ( $adcval, $zeroval, $refvolt, $refval) = @_;

    # Calculate the slope of the linear ADC -> voltage function
    my $slope= $refvolt / ($refval - $zeroval);

    # Calculate the voltage of the raw ADC value
    my $voltage= $slope * ($adcval - $zeroval);

    $voltage= 0 if ($voltage < 0);
    return ($voltage);
}

# Given a battery-id and the current ADC value, calculate the
# battery's voltage and record this into the historical database table.
# Also remove any data older than 24 hours from the database.
sub setBatteryVoltage {
    my ( $id, $adcval ) = @_;
    my @battery = getBatteryDetails($id);

    # Give up if that battery is not in the database
    return(undef) if (!@battery);
    my $timestamp = time();
    my $yesterday = $timestamp - 86400;

    # Calculate the battery's voltage
    my $voltage = getLevelAsVoltage( $adcval, $battery[2],
					      $battery[3], $battery[4] );

    # Remove outdated level data
    $dbh->do("delete from histlevels where timestamp < ?", undef, $yesterday);

    # Insert the new level and temperature data
    my $sth = $dbh->prepare(
	"insert into histlevels(id, voltage, timestamp) " .
 	"values (?,?,?)" );
    $sth->execute( $id, $voltage, $timestamp );

    return ($voltage);
}

1;
