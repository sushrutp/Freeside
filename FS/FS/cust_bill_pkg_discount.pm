package FS::cust_bill_pkg_discount;
use base qw( FS::cust_main_Mixin FS::Record );

use strict;
use FS::Record qw( dbh );

=head1 NAME

FS::cust_bill_pkg_discount - Object methods for cust_bill_pkg_discount records

=head1 SYNOPSIS

  use FS::cust_bill_pkg_discount;

  $record = new FS::cust_bill_pkg_discount \%hash;
  $record = new FS::cust_bill_pkg_discount { 'column' => 'value' };

  $error = $record->insert;

  $error = $new_record->replace($old_record);

  $error = $record->delete;

  $error = $record->check;

=head1 DESCRIPTION

An FS::cust_bill_pkg_discount object represents the slice of a customer
discount applied to a specific line item.  FS::cust_bill_pkg_discount inherits
from FS::Record.  The following fields are currently supported:

=over 4

=item billpkgdiscountnum

primary key

=item billpkgnum

Line item (see L<FS::cust_bill_pkg>)

=item pkgdiscountnum

Customer discount (see L<FS::cust_pkg_discount>)

=item amount

Amount discounted from the line itme.

=item months

Number of months of discount this represents.

=back

=head1 METHODS

=over 4

=item new HASHREF

Creates a new record.  To add the record to the database, see L<"insert">.

Note that this stores the hash reference, not a distinct copy of the hash it
points to.  You can ask the object for a copy with the I<hash> method.

=cut

# the new method can be inherited from FS::Record, if a table method is defined

sub table { 'cust_bill_pkg_discount'; }

=item insert

Adds this record to the database.  If there is an error, returns the error,
otherwise returns false.

=cut

# the insert method can be inherited from FS::Record

=item delete

Delete this record from the database.

=cut

# the delete method can be inherited from FS::Record

=item replace OLD_RECORD

Replaces the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=cut

# the replace method can be inherited from FS::Record

=item check

Checks all fields to make sure this is a valid record.  If there is
an error, returns the error, otherwise returns false.  Called by the insert
and replace methods.

=cut

sub check {
  my $self = shift;

  my $error = 
    $self->ut_numbern('billpkgdiscountnum')
    || $self->ut_foreign_key('billpkgnum', 'cust_bill_pkg', 'billpkgnum' )
    || $self->ut_foreign_key('pkgdiscountnum', 'cust_pkg_discount', 'pkgdiscountnum' )
    || $self->ut_money('amount')
    || $self->ut_float('months')
  ;
  return $error if $error;

  $self->SUPER::check;
}

=item cust_bill_pkg

Returns the associated line item (see L<FS::cust_bill_pkg>).

=item cust_pkg_discount

Returns the associated customer discount (see L<FS::cust_pkg_discount>).

=item description

Returns a string describing the discount (for use on an invoice).

=cut

sub description {
  my $self = shift;
  my $discount = $self->cust_pkg_discount->discount;

  if ( $self->months == 0 ) {
    # then this is a setup discount
    my $desc = $discount->name;
    if ( $desc ) {
      $desc .= ': ';
    } else {
      $desc = $self->mt('Setup discount of ');
    }
    if ( (my $percent = $discount->percent) > 0 ) {
      $percent = sprintf('%.1f', $percent) if $percent > int($percent);
      $percent =~ s/\.0+$//;
      $desc .= $percent . '%';
    } else {
      # note "$self->amount", not $discount->amount. if a flat discount
      # is applied to the setup fee, show the amount actually discounted.
      # we might do this for all types of discounts.
      my $money_char = FS::Conf->new->config('money_char') || '$';
      $desc .= $money_char . sprintf('%.2f', $self->amount);
    }
  
    # don't show "/month", months remaining or used, etc., as for setup
    # discounts it doesn't matter.
    return $desc;
  }

  my $desc = $discount->description_short;
  $desc .= $self->mt(' each') if $self->cust_bill_pkg->quantity > 1;

  if ( $discount->months and $self->months > 0 ) {
    # calculate months remaining on this cust_pkg_discount after this invoice
    my $date = $self->cust_bill_pkg->cust_bill->_date;
    my $used = FS::Record->scalar_sql(
      'SELECT SUM(months) FROM cust_bill_pkg_discount
      JOIN cust_bill_pkg USING (billpkgnum)
      JOIN cust_bill USING (invnum)
      WHERE pkgdiscountnum = ? AND _date <= ?',
      $self->pkgdiscountnum,
      $date
    );
    $used ||= 0;
    my $remaining = sprintf('%.2f', $discount->months - $used);
    $desc .= $self->mt(' for [quant,_1,month] ([quant,_2,month] remaining)',
              sprintf('%.2f', $self->months),
              $remaining
             );
  }
  return $desc;
}

sub _upgrade_schema {
  my ($class, %opts) = @_;

  my $sql = '
    DELETE FROM cust_bill_pkg_discount WHERE NOT EXISTS
      ( SELECT 1 FROM cust_bill_pkg WHERE cust_bill_pkg.billpkgnum = cust_bill_pkg_discount.billpkgnum )
  ';

  my $sth = dbh->prepare($sql) or die dbh->errstr;
  $sth->execute or die $sth->errstr;
  '';
}

=back

=head1 BUGS

=head1 SEE ALSO

L<FS::Record>, schema.html from the base documentation.

=cut

1;

