# {{{ BEGIN BPS TAGGED BLOCK
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2004 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# }}} END BPS TAGGED BLOCK
package RT::Interface::Email;

use strict;
use Mail::Address;
use MIME::Entity;
use RT::EmailParser;
use File::Temp;

BEGIN {
    use Exporter ();
    use vars qw ($VERSION  @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION = do { my @r = (q$Revision: 1.1.1.4 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker
    
    @ISA         = qw(Exporter);
    
    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw(
              &CreateUser
		      &GetMessageContent
		      &CheckForLoops 
		      &CheckForSuspiciousSender
		      &CheckForAutoGenerated 
		      &MailError 
		      &ParseCcAddressesFromHead
		      &ParseSenderAddressFromHead 
		      &ParseErrorsToAddressFromHead
                      &ParseAddressFromHeader
              &Gateway);

}

=head1 NAME

  RT::Interface::Email - helper functions for parsing email sent to RT

=head1 SYNOPSIS

  use lib "!!RT_LIB_PATH!!";
  use lib "!!RT_ETC_PATH!!";

  use RT::Interface::Email  qw(Gateway CreateUser);

=head1 DESCRIPTION


=begin testing

ok(require RT::Interface::Email);

=end testing


=head1 METHODS

=cut


# {{{ sub CheckForLoops 

sub CheckForLoops  {
    my $head = shift;
    
    #If this instance of RT sent it our, we don't want to take it in
    my $RTLoop = $head->get("X-RT-Loop-Prevention") || "";
    chomp ($RTLoop); #remove that newline
    if ($RTLoop eq "$RT::rtname") {
	return (1);
    }
    
    # TODO: We might not trap the case where RT instance A sends a mail
    # to RT instance B which sends a mail to ...
    return (undef);
}

# }}}

# {{{ sub CheckForSuspiciousSender

sub CheckForSuspiciousSender {
    my $head = shift;

    #if it's from a postmaster or mailer daemon, it's likely a bounce.
    
    #TODO: better algorithms needed here - there is no standards for
    #bounces, so it's very difficult to separate them from anything
    #else.  At the other hand, the Return-To address is only ment to be
    #used as an error channel, we might want to put up a separate
    #Return-To address which is treated differently.
    
    #TODO: search through the whole email and find the right Ticket ID.

    my ($From, $junk) = ParseSenderAddressFromHead($head);
    
    if (($From =~ /^mailer-daemon/i) or
	($From =~ /^postmaster/i)){
	return (1);
	
    }
    
    return (undef);

}

# }}}

# {{{ sub CheckForAutoGenerated
sub CheckForAutoGenerated {
    my $head = shift;
    
    my $Precedence = $head->get("Precedence") || "" ;
    if ($Precedence =~ /^(bulk|junk)/i) {
	return (1);
    }
    else {
	return (0);
    }
}

# }}}


# {{{ sub MailError 
sub MailError {
    my %args = (To => $RT::OwnerEmail,
		Bcc => undef,
		From => $RT::CorrespondAddress,
		Subject => 'There has been an error',
		Explanation => 'Unexplained error',
		MIMEObj => undef,
        Attach => undef,
		LogLevel => 'crit',
		@_);


    $RT::Logger->log(level => $args{'LogLevel'}, 
		     message => $args{'Explanation'}
		    );
    my $entity = MIME::Entity->build( Type  =>"multipart/mixed",
				      From => $args{'From'},
				      Bcc => $args{'Bcc'},
				      To => $args{'To'},
				      Subject => $args{'Subject'},
				      Precedence => 'bulk',
				      'X-RT-Loop-Prevention' => $RT::rtname,
				    );

    $entity->attach(  Data => $args{'Explanation'}."\n");
    
    my $mimeobj = $args{'MIMEObj'};
    if ($mimeobj) {
        $mimeobj->sync_headers();
        $entity->add_part($mimeobj);
    }
   
    if ($args{'Attach'}) {
        $entity->attach(Data => $args{'Attach'}, Type => 'message/rfc822');

    }

    if ($RT::MailCommand eq 'sendmailpipe') {
        open (MAIL, "|$RT::SendmailPath $RT::SendmailArguments") || return(0);
        print MAIL $entity->as_string;
        close(MAIL);
    }
    else {
    	$entity->send($RT::MailCommand, $RT::MailParams);
    }
}

# }}}

# {{{ Create User

sub CreateUser {
    my ($Username, $Address, $Name, $ErrorsTo, $entity) = @_;
    my $NewUser = RT::User->new($RT::SystemUser);

    my ($Val, $Message) = 
      $NewUser->Create(Name => ($Username || $Address),
                       EmailAddress => $Address,
                       RealName => $Name,
                       Password => undef,
                       Privileged => 0,
                       Comments => 'Autocreated on ticket submission'
                      );
    
    unless ($Val) {
        
        # Deal with the race condition of two account creations at once
        #
        if ($Username) {
            $NewUser->LoadByName($Username);
        }
        
        unless ($NewUser->Id) {
            $NewUser->LoadByEmail($Address);
        }
        
        unless ($NewUser->Id) {  
            MailError( To => $ErrorsTo,
                       Subject => "User could not be created",
                       Explanation => "User creation failed in mailgateway: $Message",
                       MIMEObj => $entity,
                       LogLevel => 'crit'
                     );
        }
    }

    #Load the new user object
    my $CurrentUser = RT::CurrentUser->new();
    $CurrentUser->LoadByEmail($Address);

    unless ($CurrentUser->id) {
            $RT::Logger->warning("Couldn't load user '$Address'.".  "giving up");
                MailError( To => $ErrorsTo,
                           Subject => "User could not be loaded",
                           Explanation => "User  '$Address' could not be loaded in the mail gateway",
                           MIMEObj => $entity,
                           LogLevel => 'crit'
                     );
    }

    return $CurrentUser;
}
# }}}	    
# {{{ ParseCcAddressesFromHead 

=head2 ParseCcAddressesFromHead HASHREF

Takes a hashref object containing QueueObj, Head and CurrentUser objects.
Returns a list of all email addresses in the To and Cc 
headers b<except> the current Queue\'s email addresses, the CurrentUser\'s 
email address  and anything that the configuration sub RT::IsRTAddress matches.

=cut
  
sub ParseCcAddressesFromHead {
    my %args = ( Head => undef,
		 QueueObj => undef,
		 CurrentUser => undef,
		 @_ );
    
    my (@Addresses);
        
    my @ToObjs = Mail::Address->parse($args{'Head'}->get('To'));
    my @CcObjs = Mail::Address->parse($args{'Head'}->get('Cc'));
    
    foreach my $AddrObj (@ToObjs, @CcObjs) {
	my $Address = $AddrObj->address;
	$Address = $args{'CurrentUser'}->UserObj->CanonicalizeEmailAddress($Address);
 	next if ($args{'CurrentUser'}->EmailAddress =~ /^$Address$/i);
	next if ($args{'QueueObj'}->CorrespondAddress =~ /^$Address$/i);
	next if ($args{'QueueObj'}->CommentAddress =~ /^$Address$/i);
	next if (RT::EmailParser::IsRTAddress(undef, $Address));
	
	push (@Addresses, $Address);
    }
    return (@Addresses);
}


# }}}

# {{{ ParseSenderAdddressFromHead

=head2 ParseSenderAddressFromHead

Takes a MIME::Header object. Returns a tuple: (user@host, friendly name) 
of the From (evaluated in order of Reply-To:, From:, Sender)

=cut

sub ParseSenderAddressFromHead {
    my $head = shift;
    #Figure out who's sending this message.
    my $From = $head->get('Reply-To') || 
      $head->get('From') || 
	$head->get('Sender');
    return (ParseAddressFromHeader($From));
}
# }}}

# {{{ ParseErrorsToAdddressFromHead

=head2 ParseErrorsToAddressFromHead

Takes a MIME::Header object. Return a single value : user@host
of the From (evaluated in order of Errors-To:,Reply-To:, From:, Sender)

=cut

sub ParseErrorsToAddressFromHead {
    my $head = shift;
    #Figure out who's sending this message.

    foreach my $header ('Errors-To' , 'Reply-To', 'From', 'Sender' ) {
	# If there's a header of that name
	my $headerobj = $head->get($header);
	if ($headerobj) {
		my ($addr, $name ) = ParseAddressFromHeader($headerobj);
		# If it's got actual useful content...
		return ($addr) if ($addr);
	}
    }
}
# }}}

# {{{ ParseAddressFromHeader

=head2 ParseAddressFromHeader ADDRESS

Takes an address from $head->get('Line') and returns a tuple: user@host, friendly name

=cut


sub ParseAddressFromHeader{
    my $Addr = shift;
    
    my @Addresses = Mail::Address->parse($Addr);
    
    my $AddrObj = $Addresses[0];

    unless (ref($AddrObj)) {
	return(undef,undef);
    }
 
    my $Name =  ($AddrObj->phrase || $AddrObj->comment || $AddrObj->address);
    
    #Lets take the from and load a user object.
    my $Address = $AddrObj->address;

    return ($Address, $Name);
}
# }}}



=head2 Gateway ARGSREF


Takes parameters:

    action
    queue
    message


This performs all the "guts" of the mail rt-mailgate program, and is
designed to be called from the web interface with a message, user
object, and so on.

Can also take an optional 'ticket' parameter; this ticket id overrides
any ticket id found in the subject.

Returns:

    An array of:
    
    (status code, message, optional ticket object)

    status code is a numeric value.

    for temporary failures, status code should be -75

    for permanent failures which are handled by RT, status code should be 0
    
    for succces, the status code should be 1



=cut

sub Gateway {
    my $argsref = shift;

    my %args = %$argsref;

    # Set some reasonable defaults
    $args{'action'} = 'correspond' unless ( $args{'action'} );
    $args{'queue'}  = '1'          unless ( $args{'queue'} );

    # Validate the action
    unless ( $args{'action'} =~ /^(comment|correspond|action)$/ ) {

        # Can't safely loc this. What object do we loc around?
        $RT::Logger->crit("Mail gateway called with an invalid action paramenter '".$args{'action'}."' for queue '".$args{'queue'}."'");

        return ( -75, "Invalid 'action' parameter", undef );
    }

    my $parser = RT::EmailParser->new();

    $parser->SmartParseMIMEEntityFromScalar( Message => $args{'message'});

    if (!$parser->Entity()) {
        MailError(
            To          => $RT::OwnerEmail,
            Subject     => "RT Bounce: Unparseable message",
            Explanation => "RT couldn't process the message below",
            Attach     => $args{'message'}
        );

        return(0,"Failed to parse this message. Something is likely badly wrong with the message");
    }

    my $Message = $parser->Entity();
    my $head    = $Message->head;

    my ( $CurrentUser, $AuthStat, $status, $error );

    # Initalize AuthStat so comparisons work correctly
    $AuthStat = -9999999;

    my $ErrorsTo = ParseErrorsToAddressFromHead($head);

    my $MessageId = $head->get('Message-Id')
      || "<no-message-id-" . time . rand(2000) . "\@.$RT::Organization>";

    #Pull apart the subject line
    my $Subject = $head->get('Subject') || '';
    chomp $Subject;

    $args{'ticket'} ||= $parser->ParseTicketId($Subject);

    my $SystemTicket;
    my $Right = 'CreateTicket';
    if ( $args{'ticket'} ) {
        $SystemTicket = RT::Ticket->new($RT::SystemUser);
        $SystemTicket->Load( $args{'ticket'} );
	# if there's an existing ticket, this must be a reply
	$Right = 'ReplyToTicket';
    }

    #Set up a queue object
    my $SystemQueueObj = RT::Queue->new($RT::SystemUser);
    $SystemQueueObj->Load( $args{'queue'} );

    # We can safely have no queue of we have a known-good ticket
    unless ( $args{'ticket'} || $SystemQueueObj->id ) {
        return ( -75, "RT couldn't find the queue: " . $args{'queue'}, undef );
    }

    # Authentication Level
    # -1 - Get out.  this user has been explicitly declined
    # 0 - User may not do anything (Not used at the moment)
    # 1 - Normal user
    # 2 - User is allowed to specify status updates etc. a la enhanced-mailgate

    push @RT::MailPlugins, "Auth::MailFrom" unless @RT::MailPlugins;

    # Since this needs loading, no matter what

    foreach (@RT::MailPlugins) {
        my $Code;
        my $NewAuthStat;
        if ( ref($_) eq "CODE" ) {
            $Code = $_;
        }
        else {
            $_ = "RT::Interface::Email::".$_ unless $_ =~ /^RT::Interface::Email::/;
            eval "require $_;";
            if ($@) {
                $RT::Logger->crit("Couldn't load module '$_': $@");
                next;
            }
            no strict 'refs';
            if ( !defined( $Code = *{ $_ . "::GetCurrentUser" }{CODE} ) ) {
                $RT::Logger->crit("No GetCurrentUser code found in $_ module");
                next;
            }
        }

        ( $CurrentUser, $NewAuthStat ) = $Code->(
            Message     => $Message,
            RawMessageRef => \$args{'message'},
            CurrentUser => $CurrentUser,
            AuthLevel   => $AuthStat,
            Action      => $args{'action'},
            Ticket      => $SystemTicket,
            Queue       => $SystemQueueObj
        );


        # If a module returns a "-1" then we discard the ticket, so.
        $AuthStat = -1 if $NewAuthStat == -1;

        # You get the highest level of authentication you were assigned.
        $AuthStat = $NewAuthStat if $NewAuthStat > $AuthStat;
        last if $AuthStat == -1;
    }

    # {{{ If authentication fails and no new user was created, get out.
    if ( !$CurrentUser or !$CurrentUser->Id or $AuthStat == -1 ) {

        # If the plugins refused to create one, they lose.
        unless ( $AuthStat == -1 ) {

            # Notify the RT Admin of the failure.
            # XXX Should this be configurable?
            MailError(
                To          => $RT::OwnerEmail,
                Subject     => "Could not load a valid user",
                Explanation => <<EOT,
RT could not load a valid user, and RT's configuration does not allow
for the creation of a new user for this email ($ErrorsTo).

You might need to grant 'Everyone' the right '$Right' for the
queue @{[$args{'queue'}]}.

EOT
                MIMEObj  => $Message,
                LogLevel => 'error'
            );

            # Also notify the requestor that his request has been dropped.
            MailError(
                To          => $ErrorsTo,
                Subject     => "Could not load a valid user",
                Explanation => <<EOT,
RT could not load a valid user, and RT's configuration does not allow
for the creation of a new user for your email.

EOT
                MIMEObj  => $Message,
                LogLevel => 'error'
            );
        }
        return ( 0, "Could not load a valid user", undef );
    }

    # }}}

    # {{{ Lets check for mail loops of various sorts.
    my $IsAutoGenerated = CheckForAutoGenerated($head);

    my $IsSuspiciousSender = CheckForSuspiciousSender($head);

    my $IsALoop = CheckForLoops($head);

    my $SquelchReplies = 0;

    #If the message is autogenerated, we need to know, so we can not
    # send mail to the sender
    if ( $IsSuspiciousSender || $IsAutoGenerated || $IsALoop ) {
        $SquelchReplies = 1;
        $ErrorsTo       = $RT::OwnerEmail;
    }

    # }}}

    # {{{ Drop it if it's disallowed
    if ( $AuthStat == 0 ) {
        MailError(
            To          => $ErrorsTo,
            Subject     => "Permission Denied",
            Explanation => "You do not have permission to communicate with RT",
            MIMEObj     => $Message
        );
    }

    # }}}
    # {{{ Warn someone  if it's a loop

    # Warn someone if it's a loop, before we drop it on the ground
    if ($IsALoop) {
        $RT::Logger->crit("RT Recieved mail ($MessageId) from itself.");

        #Should we mail it to RTOwner?
        if ($RT::LoopsToRTOwner) {
            MailError(
                To          => $RT::OwnerEmail,
                Subject     => "RT Bounce: $Subject",
                Explanation => "RT thinks this message may be a bounce",
                MIMEObj     => $Message
            );
        }

        #Do we actually want to store it?
        return ( 0, "Message Bounced", undef ) unless ($RT::StoreLoops);
    }

    # }}}

    # {{{ Squelch replies if necessary
    # Don't let the user stuff the RT-Squelch-Replies-To header.
    if ( $head->get('RT-Squelch-Replies-To') ) {
        $head->add(
            'RT-Relocated-Squelch-Replies-To',
            $head->get('RT-Squelch-Replies-To')
        );
        $head->delete('RT-Squelch-Replies-To');
    }

    if ($SquelchReplies) {
        ## TODO: This is a hack.  It should be some other way to
        ## indicate that the transaction should be "silent".

        my ( $Sender, $junk ) = ParseSenderAddressFromHead($head);
        $head->add( 'RT-Squelch-Replies-To', $Sender );
    }

    # }}}

    my $Ticket = RT::Ticket->new($CurrentUser);

    # {{{ If we don't have a ticket Id, we're creating a new ticket
    if ( !$args{'ticket'} ) {

        # {{{ Create a new ticket

        my @Cc;
        my @Requestors = ( $CurrentUser->id );

        if ($RT::ParseNewMessageForTicketCcs) {
            @Cc = ParseCcAddressesFromHead(
                Head        => $head,
                CurrentUser => $CurrentUser,
                QueueObj    => $SystemQueueObj
            );
        }

        my ( $id, $Transaction, $ErrStr ) = $Ticket->Create(
            Queue     => $SystemQueueObj->Id,
            Subject   => $Subject,
            Requestor => \@Requestors,
            Cc        => \@Cc,
            MIMEObj   => $Message
        );
        if ( $id == 0 ) {
            MailError(
                To          => $ErrorsTo,
                Subject     => "Ticket creation failed",
                Explanation => $ErrStr,
                MIMEObj     => $Message
            );
            $RT::Logger->error("Create failed: $id / $Transaction / $ErrStr ");
            return ( 0, "Ticket creation failed", $Ticket );
        }

        # }}}
    }

    # }}}

    #   If the action is comment, add a comment.
    elsif ( $args{'action'} =~ /^(comment|correspond)$/i ) {
        $Ticket->Load( $args{'ticket'} );
        unless ( $Ticket->Id ) {
            my $message = "Could not find a ticket with id " . $args{'ticket'};
            MailError(
                To          => $ErrorsTo,
                Subject     => "Message not recorded",
                Explanation => $message,
                MIMEObj     => $Message
            );

            return ( 0, $message );
        }

        my ( $status, $msg );
        if ( $args{'action'} =~ /^correspond$/ ) {
            ( $status, $msg ) = $Ticket->Correspond( MIMEObj => $Message );
        }
        else {
            ( $status, $msg ) = $Ticket->Comment( MIMEObj => $Message );
        }
        unless ($status) {

            #Warn the sender that we couldn't actually submit the comment.
            MailError(
                To          => $ErrorsTo,
                Subject     => "Message not recorded",
                Explanation => $msg,
                MIMEObj     => $Message
            );
            return ( 0, "Message not recorded", $Ticket );
        }
    }

    else {

        #Return mail to the sender with an error
        MailError(
            To          => $ErrorsTo,
            Subject     => "RT Configuration error",
            Explanation => "'"
              . $args{'action'}
              . "' not a recognized action."
              . " Your RT administrator has misconfigured "
              . "the mail aliases which invoke RT",
            MIMEObj => $Message
        );
        $RT::Logger->crit( $args{'action'} . " type unknown for $MessageId" );
        return (
            -75,
            "Configuration error: "
              . $args{'action'}
              . " not a recognized action",
            $Ticket
        );

    }

    return ( 1, "Success", $Ticket );
}


eval "require RT::Interface::Email_Vendor";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Interface/Email_Vendor.pm});
eval "require RT::Interface::Email_Local";
die $@ if ($@ && $@ !~ qr{^Can't locate RT/Interface/Email_Local.pm});

1;
