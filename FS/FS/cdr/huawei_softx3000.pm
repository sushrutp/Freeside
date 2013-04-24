package FS::cdr::huawei_softx3000;
use base qw( FS::cdr );

use strict;
use vars qw( %info %TZ );
use subs qw( ts24008_number TimeStamp );
use Time::Local;
use FS::Record qw( qsearch );
use FS::cdr_calltype;

#false laziness w/gsm_tap3_12.pm
%TZ = (
  '+0000' => 'XXX-0',
  '+0100' => 'XXX-1',
  '+0200' => 'XXX-2',
  '+0300' => 'XXX-3',
  '+0400' => 'XXX-4',
  '+0500' => 'XXX-5',
  '+0600' => 'XXX-6',
  '+0700' => 'XXX-7',
  '+0800' => 'XXX-8',
  '+0900' => 'XXX-9',
  '+1000' => 'XXX-10',
  '+1100' => 'XXX-11',
  '+1200' => 'XXX-12',
  '-0000' => 'XXX+0',
  '-0100' => 'XXX+1',
  '-0200' => 'XXX+2',
  '-0300' => 'XXX+3',
  '-0400' => 'XXX+4',
  '-0500' => 'XXX+5',
  '-0600' => 'XXX+6',
  '-0700' => 'XXX+7',
  '-0800' => 'XXX+8',
  '-0900' => 'XXX+9',
  '-1000' => 'XXX+10',
  '-1100' => 'XXX+11',
  '-1200' => 'XXX+12',
);

%info = (
  'name'          => 'Huawei SoftX3000', #V100R006C05 ?
  'weight'        => 160,
  'type'          => 'asn.1',
  'import_fields' => [],
  'asn_format'    => {
    'spec' => _asn_spec(),
    'macro'         => 'CallEventDataFile',
    'header_buffer' => sub {
      #my $CallEventDataFile = shift;

      my %cdr_calltype = ( map { $_->calltypename => $_->calltypenum }
                             qsearch('cdr_calltype', {})
                         );

      { cdr_calltype => \%cdr_calltype,
      };

    },
    'arrayref'      => sub { shift->{'callEventRecords'} },
    'row_callback'  => sub {
      my( $row, $buffer ) = @_;
      my @keys = keys %$row;
      $buffer->{'key'} = $keys[0];
    },
    'map'           => {
      'src'           => huawei_field('callingNumber', ts24008_number, ),

      'dst'           => huawei_field('calledNumber',  ts24008_number, ),

      'startdate'     => huawei_field(['answerTime','deliveryTime'], TimeStamp),
      'answerdate'    => huawei_field(['answerTime','deliveryTime'], TimeStamp),
      'enddate'       => huawei_field('releaseTime', TimeStamp),
      'duration'      => huawei_field('callDuration'),
      'billsec'       => huawei_field('callDuration'),
      #'disposition'   => #diagnostics?
      #'accountcode'
      #'charged_party' => # 0 or 1, do something with this?
      'calltypenum'   => sub {
        my($rec, $buf) = @_;
        my $key = $buf->{key};
        $buf->{'cdr_calltype'}{ $key };
      },
      #'carrierid' =>
    },

  },
);

sub huawei_field {
  my $field = shift;
  my $decode = $_[0] ? shift : '';
  return sub {
    my($rec, $buf) = @_;

    my $key = $buf->{key};

    $field = ref($field) ? $field : [ $field ];
    my $value = '';
    foreach my $f (@$field) {
      $value = $rec->{$key}{$f} and last;
    }

    $decode
      ? &{ $decode }( $value )
      : $value;

  };
}

sub ts24008_number {
  # This type contains the binary coded decimal representation of
  # a directory number e.g. calling/called/connected/translated number.
  # The encoding of the octet string is in accordance with the
  # the elements "Calling party BCD number", "Called party BCD number"
  # and "Connected number" defined in TS 24.008.
  # This encoding includes type of number and number plan information
  # together with a BCD encoded digit string.
  # It may also contain both a presentation and screening indicator
  # (octet 3a).
  # For the avoidance of doubt, this field does not include
  # octets 1 and 2, the element name and length, as this would be
  # redundant.
  #
  #type id (per TS 24.008 page 490):
  #          low nybble: "numbering plan identification"
  #         high nybble: "type of number"
  #                      0 unknown
  #                      1 international
  #                      2 national
  #                      3 network specific
  #                      4 dedicated access, short code
  #                      5 reserved
  #                      6 reserved
  #                      7 reserved for extension
  #                   (bit 8 "extension")
  return sub {
    my( $type_id, $value ) = unpack 'Ch*', shift;
    $value =~ s/f$//; # If the called party BCD number contains an odd number
                      # of digits, bits 5 to 8 of the last octet shall be
                      # filled with an end mark coded as "1111".
    $value;
  };
}

sub TimeStamp {
  # The contents of this field are a compact form of the UTCTime format
  # containing local time plus an offset to universal time. Binary coded
  # decimal encoding is employed for the digits to reduce the storage and
  # transmission overhead
  # e.g. YYMMDDhhmmssShhmm
  # where
  # YY    =    Year 00 to 99        BCD encoded
  # MM    =    Month 01 to 12       BCD encoded
  # DD    =    Day 01 to 31         BCD encoded
  # hh    =    hour 00 to 23        BCD encoded
  # mm    =    minute 00 to 59      BCD encoded
  # ss    =    second 00 to 59      BCD encoded
  # S     =    Sign 0 = "+", "-"    ASCII encoded
  # hh    =    hour 00 to 23        BCD encoded
  # mm    =    minute 00 to 59      BCD encoded
  return sub {
    my($year, $mon, $day, $hour, $min, $sec, $tz_sign, $tz_hour, $tz_min, $dst)=
      unpack 'H2H2H2H2H2H2AH2H2C', shift;  
    #warn "$year/$mon/$day $hour:$min:$sec $tz_sign$tz_hour$tz_min $dst\n";
    return 0 unless $year; #y2100 bug
    local($ENV{TZ}) = $TZ{ "$tz_sign$tz_hour$tz_min" };
    timelocal($sec, $min, $hour, $day, $mon-1, $year);
  };
}

sub _asn_spec {
  <<'END';

--DEFINITIONS IMPLICIT TAGS    ::=

--BEGIN

--------------------------------------------------------------------------------
--
--  CALL AND EVENT RECORDS
--
------------------------------------------------------------------------------
--Font: verdana  8

CallEventRecord    ::= CHOICE
{
    moCallRecord              [0] MOCallRecord,
    mtCallRecord              [1] MTCallRecord,
    roamingRecord             [2] RoamingRecord,
    incGatewayRecord          [3] IncGatewayRecord,
    outGatewayRecord          [4] OutGatewayRecord,
    transitRecord             [5] TransitCallRecord,
    moSMSRecord               [6] MOSMSRecord,
    mtSMSRecord               [7] MTSMSRecord,
    ssActionRecord           [10] SSActionRecord,
    hlrIntRecord             [11] HLRIntRecord,
    commonEquipRecord        [14] CommonEquipRecord,
    recTypeExtensions        [15] ManagementExtensions,
    termCAMELRecord          [16] TermCAMELRecord,
    mtLCSRecord              [17] MTLCSRecord,
    moLCSRecord              [18] MOLCSRecord,
    niLCSRecord              [19] NILCSRecord,
    forwardCallRecord       [100] MOCallRecord
}

MOCallRecord    ::= SET
{
    recordType                            [0] CallEventRecordType                          OPTIONAL,
    servedIMSI                            [1] IMSI                                         OPTIONAL,
    servedIMEI                            [2] IMEI                                         OPTIONAL,
    servedMSISDN                          [3] MSISDN                                       OPTIONAL,
    callingNumber                         [4] CallingNumber                                OPTIONAL,
    calledNumber                          [5] CalledNumber                                 OPTIONAL,
    translatedNumber                      [6] TranslatedNumber                             OPTIONAL,
    connectedNumber                       [7] ConnectedNumber                              OPTIONAL,
    roamingNumber                         [8] RoamingNumber                                OPTIONAL,
    recordingEntity                       [9] RecordingEntity                              OPTIONAL,
    mscIncomingROUTE                     [10] ROUTE                                        OPTIONAL,
    mscOutgoingROUTE                     [11] ROUTE                                        OPTIONAL,
    location                             [12] LocationAreaAndCell                          OPTIONAL,
    changeOfLocation                     [13] SEQUENCE OF LocationChange                   OPTIONAL,
    basicService                         [14] BasicServiceCode                             OPTIONAL,
    transparencyIndicator                [15] TransparencyInd                              OPTIONAL,
    changeOfService                      [16] SEQUENCE OF ChangeOfService                  OPTIONAL,
    supplServicesUsed                    [17] SEQUENCE OF  SuppServiceUsed                 OPTIONAL,
    aocParameters                        [18] AOCParameters                                OPTIONAL,
    changeOfAOCParms                     [19] SEQUENCE OF AOCParmChange                    OPTIONAL,
    msClassmark                          [20] Classmark                                    OPTIONAL,
    changeOfClassmark                    [21] ChangeOfClassmark                            OPTIONAL,
    seizureTime                          [22] TimeStamp                                    OPTIONAL,
    answerTime                           [23] TimeStamp                                    OPTIONAL,
    releaseTime                          [24] TimeStamp                                    OPTIONAL,
    callDuration                         [25] CallDuration                                 OPTIONAL,
    radioChanRequested                   [27] RadioChanRequested                           OPTIONAL,
    radioChanUsed                        [28] TrafficChannel                               OPTIONAL,
    changeOfRadioChan                    [29] ChangeOfRadioChannel                         OPTIONAL,
    causeForTerm                         [30] CauseForTerm                                 OPTIONAL,
    diagnostics                          [31] Diagnostics                                  OPTIONAL,
    callReference                        [32] CallReference                                OPTIONAL,
    sequenceNumber                       [33] SequenceNumber                               OPTIONAL,
    additionalChgInfo                    [34] AdditionalChgInfo                            OPTIONAL,
    recordExtensions                     [35] ManagementExtensions                         OPTIONAL,
    gsm-SCFAddress                       [36] Gsm-SCFAddress                               OPTIONAL,
    serviceKey                           [37] ServiceKey                                   OPTIONAL,
    networkCallReference                 [38] NetworkCallReference                         OPTIONAL,
    mSCAddress                           [39] MSCAddress                                   OPTIONAL,
    cAMELInitCFIndicator                 [40] CAMELInitCFIndicator                         OPTIONAL,
    defaultCallHandling                  [41] DefaultCallHandling                          OPTIONAL,
    fnur                                 [45] Fnur                                         OPTIONAL,
    aiurRequested                        [46] AiurRequested                                OPTIONAL,
    speechVersionSupported               [49] SpeechVersionIdentifier                      OPTIONAL,
    speechVersionUsed                    [50] SpeechVersionIdentifier                      OPTIONAL,
    numberOfDPEncountered                [51] INTEGER                                      OPTIONAL,
    levelOfCAMELService                  [52] LevelOfCAMELService                          OPTIONAL,
    freeFormatData                       [53] FreeFormatData                               OPTIONAL,
    cAMELCallLegInformation              [54] SEQUENCE OF CAMELInformation                 OPTIONAL,
    freeFormatDataAppend                 [55] BOOLEAN                                      OPTIONAL,
    defaultCallHandling-2                [56] DefaultCallHandling                          OPTIONAL,
    gsm-SCFAddress-2                     [57] Gsm-SCFAddress                               OPTIONAL,
    serviceKey-2                         [58] ServiceKey                                   OPTIONAL,
    freeFormatData-2                     [59] FreeFormatData                               OPTIONAL,
    freeFormatDataAppend-2               [60] BOOLEAN                                      OPTIONAL,
    systemType                           [61] SystemType                                   OPTIONAL,
    rateIndication                       [62] RateIndication                               OPTIONAL,
    partialRecordType                    [69] PartialRecordType                            OPTIONAL,
    guaranteedBitRate                    [70] GuaranteedBitRate                            OPTIONAL,
    maximumBitRate                       [71] MaximumBitRate                               OPTIONAL,
    modemType                           [139] ModemType                                    OPTIONAL,
    classmark3                          [140] Classmark3                                   OPTIONAL,
    chargedParty                        [141] ChargedParty                                 OPTIONAL,
    originalCalledNumber                [142] OriginalCalledNumber                         OPTIONAL,
    callingChargeAreaCode               [145] ChargeAreaCode                               OPTIONAL,
    calledChargeAreaCode                [146] ChargeAreaCode                               OPTIONAL,
    mscOutgoingCircuit                  [166] MSCCIC                                       OPTIONAL,
    orgRNCorBSCId                       [167] RNCorBSCId                                   OPTIONAL,
    orgMSCId                            [168] MSCId                                        OPTIONAL,
    callEmlppPriority                   [170] EmlppPriority                                OPTIONAL,
    callerDefaultEmlppPriority          [171] EmlppPriority                                OPTIONAL,
    eaSubscriberInfo                    [174] EASubscriberInfo                             OPTIONAL,
    selectedCIC                         [175] SelectedCIC                                  OPTIONAL,
    optimalRoutingFlag                  [177] NULL                                         OPTIONAL,
    optimalRoutingLateForwardFlag       [178] NULL                                         OPTIONAL,
    optimalRoutingEarlyForwardFlag      [179] NULL                                         OPTIONAL,
    portedflag                          [180] PortedFlag                                   OPTIONAL,
    calledIMSI                          [181] IMSI                                         OPTIONAL,
    globalAreaID                        [188] GAI                                          OPTIONAL,
    changeOfglobalAreaID                [189] SEQUENCE OF ChangeOfglobalAreaID             OPTIONAL,
    subscriberCategory                  [190] SubscriberCategory                           OPTIONAL,
    firstmccmnc                         [192] MCCMNC                                       OPTIONAL,
    intermediatemccmnc                  [193] MCCMNC                                       OPTIONAL,
    lastmccmnc                          [194] MCCMNC                                       OPTIONAL,
    cUGOutgoingAccessIndicator          [195] CUGOutgoingAccessIndicator                   OPTIONAL,
    cUGInterlockCode                    [196] CUGInterlockCode                             OPTIONAL,
    cUGOutgoingAccessUsed               [197] CUGOutgoingAccessUsed                        OPTIONAL,
    cUGIndex                            [198] CUGIndex                                     OPTIONAL,
    interactionWithIP                   [199] InteractionWithIP                            OPTIONAL,
    hotBillingTag                       [200] HotBillingTag                                OPTIONAL,
    setupTime                           [201] TimeStamp                                    OPTIONAL,
    alertingTime                        [202] TimeStamp                                    OPTIONAL,
    voiceIndicator                      [203] VoiceIndicator                               OPTIONAL,
    bCategory                           [204] BCategory                                    OPTIONAL,
    callType                            [205] CallType                                     OPTIONAL
}

--at moc     callingNumber is the same as served msisdn except basic msisdn != calling number such as MSP service

MTCallRecord            ::= SET
{
    recordType                            [0] CallEventRecordType                          OPTIONAL,
    servedIMSI                            [1] IMSI                                         OPTIONAL,
    servedIMEI                            [2] IMEI                                         OPTIONAL,
    servedMSISDN                          [3] CalledNumber                                 OPTIONAL,
    callingNumber                         [4] CallingNumber                                OPTIONAL,
    connectedNumber                       [5] ConnectedNumber                              OPTIONAL,
    recordingEntity                       [6] RecordingEntity                              OPTIONAL,
    mscIncomingROUTE                      [7] ROUTE                                        OPTIONAL,
    mscOutgoingROUTE                      [8] ROUTE                                        OPTIONAL,
    location                              [9] LocationAreaAndCell                          OPTIONAL,
    changeOfLocation                     [10] SEQUENCE OF LocationChange                   OPTIONAL,
    basicService                         [11] BasicServiceCode                             OPTIONAL,
    transparencyIndicator                [12] TransparencyInd                              OPTIONAL,
    changeOfService                      [13] SEQUENCE OF ChangeOfService                  OPTIONAL,
    supplServicesUsed                    [14] SEQUENCE OF SuppServiceUsed                  OPTIONAL,
    aocParameters                        [15] AOCParameters                                OPTIONAL,
    changeOfAOCParms                     [16] SEQUENCE OF AOCParmChange                    OPTIONAL,
    msClassmark                          [17] Classmark                                    OPTIONAL,
    changeOfClassmark                    [18] ChangeOfClassmark                            OPTIONAL,
    seizureTime                          [19] TimeStamp                                    OPTIONAL,
    answerTime                           [20] TimeStamp                                    OPTIONAL,
    releaseTime                          [21] TimeStamp                                    OPTIONAL,
    callDuration                         [22] CallDuration                                 OPTIONAL,
    radioChanRequested                   [24] RadioChanRequested                           OPTIONAL,
    radioChanUsed                        [25] TrafficChannel                               OPTIONAL,
    changeOfRadioChan                    [26] ChangeOfRadioChannel                         OPTIONAL,
    causeForTerm                         [27] CauseForTerm                                 OPTIONAL,
    diagnostics                          [28] Diagnostics                                  OPTIONAL,
    callReference                        [29] CallReference                                OPTIONAL,
    sequenceNumber                       [30] SequenceNumber                               OPTIONAL,
    additionalChgInfo                    [31] AdditionalChgInfo                            OPTIONAL,
    recordExtensions                     [32] ManagementExtensions                         OPTIONAL,
    networkCallReference                 [33] NetworkCallReference                         OPTIONAL,
    mSCAddress                           [34] MSCAddress                                   OPTIONAL,
    fnur                                 [38] Fnur                                         OPTIONAL,
    aiurRequested                        [39] AiurRequested                                OPTIONAL,
    speechVersionSupported               [42] SpeechVersionIdentifier                      OPTIONAL,
    speechVersionUsed                    [43] SpeechVersionIdentifier                      OPTIONAL,
    gsm-SCFAddress                       [44] Gsm-SCFAddress                               OPTIONAL,
    serviceKey                           [45] ServiceKey                                   OPTIONAL,
    systemType                           [46] SystemType                                   OPTIONAL,
    rateIndication                       [47] RateIndication                               OPTIONAL,
    partialRecordType                    [54] PartialRecordType                            OPTIONAL,
    guaranteedBitRate                    [55] GuaranteedBitRate                            OPTIONAL,
    maximumBitRate                       [56] MaximumBitRate                               OPTIONAL,
    initialCallAttemptFlag              [137] NULL                                         OPTIONAL,
    ussdCallBackFlag                    [138] NULL                                         OPTIONAL,
    modemType                           [139] ModemType                                    OPTIONAL,
    classmark3                          [140] Classmark3                                   OPTIONAL,
    chargedParty                        [141] ChargedParty                                 OPTIONAL,
    originalCalledNumber                [142] OriginalCalledNumber                         OPTIONAL,
    callingChargeAreaCode               [145]ChargeAreaCode                                OPTIONAL,
    calledChargeAreaCode                [146]ChargeAreaCode                                OPTIONAL,
    defaultCallHandling                 [150] DefaultCallHandling                          OPTIONAL,
    freeFormatData                      [151] FreeFormatData                               OPTIONAL,
    freeFormatDataAppend                [152] BOOLEAN                                      OPTIONAL,
    numberOfDPEncountered               [153] INTEGER                                      OPTIONAL,
    levelOfCAMELService                 [154] LevelOfCAMELService                          OPTIONAL,
    roamingNumber                       [160] RoamingNumber                                OPTIONAL,
    mscIncomingCircuit                  [166] MSCCIC                                       OPTIONAL,
    orgRNCorBSCId                       [167] RNCorBSCId                                   OPTIONAL,
    orgMSCId                            [168] MSCId                                        OPTIONAL,
    callEmlppPriority                   [170] EmlppPriority                                OPTIONAL,
    calledDefaultEmlppPriority          [171] EmlppPriority                                OPTIONAL,
    eaSubscriberInfo                    [174] EASubscriberInfo                             OPTIONAL,
    selectedCIC                         [175] SelectedCIC                                  OPTIONAL,
    optimalRoutingFlag                  [177] NULL                                         OPTIONAL,
    portedflag                          [180] PortedFlag                                   OPTIONAL,
    globalAreaID                        [188] GAI                                          OPTIONAL,
    changeOfglobalAreaID                [189] SEQUENCE OF ChangeOfglobalAreaID             OPTIONAL,
    subscriberCategory                  [190] SubscriberCategory                           OPTIONAL,
    firstmccmnc                         [192] MCCMNC                                       OPTIONAL,
    intermediatemccmnc                  [193] MCCMNC                                       OPTIONAL,
    lastmccmnc                          [194] MCCMNC                                       OPTIONAL,
    cUGOutgoingAccessIndicator          [195] CUGOutgoingAccessIndicator                   OPTIONAL,
    cUGInterlockCode                    [196] CUGInterlockCode                             OPTIONAL,
    cUGIncomingAccessUsed               [197] CUGIncomingAccessUsed                        OPTIONAL,
    cUGIndex                            [198] CUGIndex                                     OPTIONAL,
    hotBillingTag                       [200] HotBillingTag                                OPTIONAL,
    redirectingnumber                   [201] RedirectingNumber                            OPTIONAL,
    redirectingcounter                  [202] RedirectingCounter                           OPTIONAL,
    setupTime                           [203] TimeStamp                                    OPTIONAL,
    alertingTime                        [204] TimeStamp                                    OPTIONAL,
    calledNumber                        [205] CalledNumber                                 OPTIONAL,
    voiceIndicator                      [206] VoiceIndicator                               OPTIONAL,
    bCategory                           [207] BCategory                                    OPTIONAL,
    callType                            [208] CallType                                     OPTIONAL
}

RoamingRecord            ::= SET
{
    recordType                            [0] CallEventRecordType                          OPTIONAL,
    servedIMSI                            [1] IMSI                                         OPTIONAL,
    servedMSISDN                          [2] MSISDN                                       OPTIONAL,
    callingNumber                         [3] CallingNumber                                OPTIONAL,
    roamingNumber                         [4] RoamingNumber                                OPTIONAL,
    recordingEntity                       [5] RecordingEntity                              OPTIONAL,
    mscIncomingROUTE                      [6] ROUTE                                        OPTIONAL,
    mscOutgoingROUTE                      [7] ROUTE                                        OPTIONAL,
    basicService                          [8] BasicServiceCode                             OPTIONAL,
    transparencyIndicator                 [9] TransparencyInd                              OPTIONAL,
    changeOfService                      [10] SEQUENCE OF ChangeOfService                  OPTIONAL,
    supplServicesUsed                    [11] SEQUENCE OF  SuppServiceUsed                 OPTIONAL,
    seizureTime                          [12] TimeStamp                                    OPTIONAL,
    answerTime                           [13] TimeStamp                                    OPTIONAL,
    releaseTime                          [14] TimeStamp                                    OPTIONAL,
    callDuration                         [15] CallDuration                                 OPTIONAL,
    causeForTerm                         [17] CauseForTerm                                 OPTIONAL,
    diagnostics                          [18] Diagnostics                                  OPTIONAL,
    callReference                        [19] CallReference                                OPTIONAL,
    sequenceNumber                       [20] SequenceNumber                               OPTIONAL,
    recordExtensions                     [21] ManagementExtensions                         OPTIONAL,
    networkCallReference                 [22] NetworkCallReference                         OPTIONAL,
    mSCAddress                           [23] MSCAddress                                   OPTIONAL,
    partialRecordType                    [30] PartialRecordType                            OPTIONAL,
    additionalChgInfo                   [133] AdditionalChgInfo                            OPTIONAL,
    chargedParty                        [141] ChargedParty                                 OPTIONAL,
    originalCalledNumber                [142] OriginalCalledNumber                         OPTIONAL,
    callingChargeAreaCode               [145] ChargeAreaCode                               OPTIONAL,
    calledChargeAreaCode                [146] ChargeAreaCode                               OPTIONAL,
    mscOutgoingCircuit                  [166] MSCCIC                                       OPTIONAL,
    mscIncomingCircuit                  [167] MSCCIC                                       OPTIONAL,
    orgMSCId                            [168] MSCId                                        OPTIONAL,
    callEmlppPriority                   [170] EmlppPriority                                OPTIONAL,
    eaSubscriberInfo                    [174] EASubscriberInfo                             OPTIONAL,
    selectedCIC                         [175] SelectedCIC                                  OPTIONAL,
    optimalRoutingFlag                  [177] NULL                                         OPTIONAL,
    subscriberCategory                  [190] SubscriberCategory                           OPTIONAL,
    cUGOutgoingAccessIndicator          [195] CUGOutgoingAccessIndicator                   OPTIONAL,
    cUGInterlockCode                    [196] CUGInterlockCode                             OPTIONAL,
    hotBillingTag                       [200] HotBillingTag                                OPTIONAL
}

TermCAMELRecord    ::= SET
{
    recordtype                            [0] CallEventRecordType                          OPTIONAL,
    servedIMSI                            [1] IMSI                                         OPTIONAL,
    servedMSISDN                          [2] MSISDN                                       OPTIONAL,
    recordingEntity                       [3] RecordingEntity                              OPTIONAL,
    interrogationTime                     [4] TimeStamp                                    OPTIONAL,
    destinationRoutingAddress             [5] DestinationRoutingAddress                    OPTIONAL,
    gsm-SCFAddress                        [6] Gsm-SCFAddress                               OPTIONAL,
    serviceKey                            [7] ServiceKey                                   OPTIONAL,
    networkCallReference                  [8] NetworkCallReference                         OPTIONAL,
    mSCAddress                            [9] MSCAddress                                   OPTIONAL,
    defaultCallHandling                  [10] DefaultCallHandling                          OPTIONAL,
    recordExtensions                     [11] ManagementExtensions                         OPTIONAL,
    calledNumber                         [12] CalledNumber                                 OPTIONAL,
    callingNumber                        [13] CallingNumber                                OPTIONAL,
    mscIncomingROUTE                     [14] ROUTE                                        OPTIONAL,
    mscOutgoingROUTE                     [15] ROUTE                                        OPTIONAL,
    seizureTime                          [16] TimeStamp                                    OPTIONAL,
    answerTime                           [17] TimeStamp                                    OPTIONAL,
    releaseTime                          [18] TimeStamp                                    OPTIONAL,
    callDuration                         [19] CallDuration                                 OPTIONAL,
    causeForTerm                         [21] CauseForTerm                                 OPTIONAL,
    diagnostics                          [22] Diagnostics                                  OPTIONAL,
    callReference                        [23] CallReference                                OPTIONAL,
    sequenceNumber                       [24] SequenceNumber                               OPTIONAL,
    numberOfDPEncountered                [25] INTEGER                                      OPTIONAL,
    levelOfCAMELService                  [26] LevelOfCAMELService                          OPTIONAL,
    freeFormatData                       [27] FreeFormatData                               OPTIONAL,
    cAMELCallLegInformation              [28] SEQUENCE OF CAMELInformation                 OPTIONAL,
    freeFormatDataAppend                 [29] BOOLEAN                                      OPTIONAL,
    mscServerIndication                  [30] BOOLEAN                                      OPTIONAL,
    defaultCallHandling-2                [31] DefaultCallHandling                          OPTIONAL,
    gsm-SCFAddress-2                     [32] Gsm-SCFAddress                               OPTIONAL,
    serviceKey-2                         [33] ServiceKey                                   OPTIONAL,
    freeFormatData-2                     [34] FreeFormatData                               OPTIONAL,
    freeFormatDataAppend-2               [35] BOOLEAN                                      OPTIONAL,
    partialRecordType                    [42] PartialRecordType                            OPTIONAL,
    basicService                        [130] BasicServiceCode                             OPTIONAL,
    additionalChgInfo                   [133] AdditionalChgInfo                            OPTIONAL,
    chargedParty                        [141] ChargedParty                                 OPTIONAL,
    originalCalledNumber                [142] OriginalCalledNumber                         OPTIONAL,
    orgMSCId                            [168] MSCId                                        OPTIONAL,
    subscriberCategory                  [190] SubscriberCategory                           OPTIONAL,
    hotBillingTag                       [200] HotBillingTag                                OPTIONAL
}

IncGatewayRecord        ::= SET
{
    recordType                            [0] CallEventRecordType                          OPTIONAL,
    callingNumber                         [1] CallingNumber                                OPTIONAL,
    calledNumber                          [2] CalledNumber                                 OPTIONAL,
    recordingEntity                       [3] RecordingEntity                              OPTIONAL,
    mscIncomingROUTE                      [4] ROUTE                                        OPTIONAL,
    mscOutgoingROUTE                      [5] ROUTE                                        OPTIONAL,
    seizureTime                           [6] TimeStamp                                    OPTIONAL,
    answerTime                            [7] TimeStamp                                    OPTIONAL,
    releaseTime                           [8] TimeStamp                                    OPTIONAL,
    callDuration                          [9] CallDuration                                 OPTIONAL,
    causeForTerm                         [11] CauseForTerm                                 OPTIONAL,
    diagnostics                          [12] Diagnostics                                  OPTIONAL,
    callReference                        [13] CallReference                                OPTIONAL,
    sequenceNumber                       [14] SequenceNumber                               OPTIONAL,
    recordExtensions                     [15] ManagementExtensions                         OPTIONAL,
    partialRecordType                    [22] PartialRecordType                            OPTIONAL,
    iSDN-BC                              [23] ISDN-BC                                      OPTIONAL,
    lLC                                  [24] LLC                                          OPTIONAL,
    hLC                                  [25] HLC                                          OPTIONAL,
    basicService                        [130] BasicServiceCode                             OPTIONAL,
    additionalChgInfo                   [133] AdditionalChgInfo                            OPTIONAL,
    chargedParty                        [141] ChargedParty                                 OPTIONAL,
    originalCalledNumber                [142] OriginalCalledNumber                         OPTIONAL,
    rateIndication                      [159] RateIndication                               OPTIONAL,
    roamingNumber                       [160] RoamingNumber                                OPTIONAL,
    mscIncomingCircuit                  [167] MSCCIC                                       OPTIONAL,
    orgMSCId                            [168] MSCId                                        OPTIONAL,
    callEmlppPriority                   [170] EmlppPriority                                OPTIONAL,
    eaSubscriberInfo                    [174] EASubscriberInfo                             OPTIONAL,
    selectedCIC                         [175] SelectedCIC                                  OPTIONAL,
    cUGOutgoingAccessIndicator          [195] CUGOutgoingAccessIndicator                   OPTIONAL,
    cUGInterlockCode                    [196] CUGInterlockCode                             OPTIONAL,
    cUGIncomingAccessUsed               [197] CUGIncomingAccessUsed                        OPTIONAL,
    mscIncomingRouteAttribute           [198] RouteAttribute                               OPTIONAL,
    mscOutgoingRouteAttribute           [199] RouteAttribute                               OPTIONAL,
    networkCallReference                [200] NetworkCallReference                         OPTIONAL,
    setupTime                           [201] TimeStamp                                    OPTIONAL,
    alertingTime                        [202] TimeStamp                                    OPTIONAL,
    voiceIndicator                      [203] VoiceIndicator                               OPTIONAL,
    bCategory                           [204] BCategory                                    OPTIONAL,
    callType                            [205] CallType                                     OPTIONAL
}

OutGatewayRecord        ::= SET
{
    recordType                            [0] CallEventRecordType                          OPTIONAL,
    callingNumber                         [1] CallingNumber                                OPTIONAL,
    calledNumber                          [2] CalledNumber                                 OPTIONAL,
    recordingEntity                       [3] RecordingEntity                              OPTIONAL,
    mscIncomingROUTE                      [4] ROUTE                                        OPTIONAL,
    mscOutgoingROUTE                      [5] ROUTE                                        OPTIONAL,
    seizureTime                           [6] TimeStamp                                    OPTIONAL,
    answerTime                            [7] TimeStamp                                    OPTIONAL,
    releaseTime                           [8] TimeStamp                                    OPTIONAL,
    callDuration                          [9] CallDuration                                 OPTIONAL,
    causeForTerm                         [11] CauseForTerm                                 OPTIONAL,
    diagnostics                          [12] Diagnostics                                  OPTIONAL,
    callReference                        [13] CallReference                                OPTIONAL,
    sequenceNumber                       [14] SequenceNumber                               OPTIONAL,
    recordExtensions                     [15] ManagementExtensions                         OPTIONAL,
    partialRecordType                    [22] PartialRecordType                            OPTIONAL,
    basicService                        [130] BasicServiceCode                             OPTIONAL,
    additionalChgInfo                   [133] AdditionalChgInfo                            OPTIONAL,
    chargedParty                        [141] ChargedParty                                 OPTIONAL,
    originalCalledNumber                [142] OriginalCalledNumber                         OPTIONAL,
    rateIndication                      [159] RateIndication                               OPTIONAL,
    roamingNumber                       [160] RoamingNumber                                OPTIONAL,
    mscOutgoingCircuit                  [166] MSCCIC                                       OPTIONAL,
    orgMSCId                            [168] MSCId                                        OPTIONAL,
    eaSubscriberInfo                    [174] EASubscriberInfo                             OPTIONAL,
    selectedCIC                         [175] SelectedCIC                                  OPTIONAL,
    callEmlppPriority                   [170] EmlppPriority                                OPTIONAL,
    cUGOutgoingAccessIndicator          [195] CUGOutgoingAccessIndicator                   OPTIONAL,
    cUGInterlockCode                    [196] CUGInterlockCode                             OPTIONAL,
    cUGIncomingAccessUsed               [197] CUGIncomingAccessUsed                        OPTIONAL,
    mscIncomingRouteAttribute           [198] RouteAttribute                               OPTIONAL,
    mscOutgoingRouteAttribute           [199] RouteAttribute                               OPTIONAL,
    networkCallReference                [200] NetworkCallReference                         OPTIONAL,
    setupTime                           [201] TimeStamp                                    OPTIONAL,
    alertingTime                        [202] TimeStamp                                    OPTIONAL,
    voiceIndicator                      [203] VoiceIndicator                               OPTIONAL,
    bCategory                           [204] BCategory                                    OPTIONAL,
    callType                            [205] CallType                                     OPTIONAL
}

TransitCallRecord        ::= SET
{
    recordType                            [0] CallEventRecordType                          OPTIONAL,
    recordingEntity                       [1] RecordingEntity                              OPTIONAL,
    mscIncomingROUTE                      [2] ROUTE                                        OPTIONAL,
    mscOutgoingROUTE                      [3] ROUTE                                        OPTIONAL,
    callingNumber                         [4] CallingNumber                                OPTIONAL,
    calledNumber                          [5] CalledNumber                                 OPTIONAL,
    isdnBasicService                      [6] BasicService                                 OPTIONAL,
    seizureTime                           [7] TimeStamp                                    OPTIONAL,
    answerTime                            [8] TimeStamp                                    OPTIONAL,
    releaseTime                           [9] TimeStamp                                    OPTIONAL,
    callDuration                         [10] CallDuration                                 OPTIONAL,
    causeForTerm                         [12] CauseForTerm                                 OPTIONAL,
    diagnostics                          [13] Diagnostics                                  OPTIONAL,
    callReference                        [14] CallReference                                OPTIONAL,
    sequenceNumber                       [15] SequenceNumber                               OPTIONAL,
    recordExtensions                     [16] ManagementExtensions                         OPTIONAL,
    partialRecordType                    [23] PartialRecordType                            OPTIONAL,
    basicService                        [130] BasicServiceCode                             OPTIONAL,
    additionalChgInfo                   [133] AdditionalChgInfo                            OPTIONAL,
    originalCalledNumber                [142] OriginalCalledNumber                         OPTIONAL,
    rateIndication                      [159] RateIndication                               OPTIONAL,
    mscOutgoingCircuit                  [166] MSCCIC                                       OPTIONAL,
    mscIncomingCircuit                  [167] MSCCIC                                       OPTIONAL,
    orgMSCId                            [168] MSCId                                        OPTIONAL,
    callEmlppPriority                   [170] EmlppPriority                                OPTIONAL,
    eaSubscriberInfo                    [174] EASubscriberInfo                             OPTIONAL,
    selectedCIC                         [175] SelectedCIC                                  OPTIONAL,
    cUGOutgoingAccessIndicator          [195] CUGOutgoingAccessIndicator                   OPTIONAL,
    cUGInterlockCode                    [196] CUGInterlockCode                             OPTIONAL,
    cUGIncomingAccessUsed               [197] CUGIncomingAccessUsed                        OPTIONAL,
    mscIncomingRouteAttribute           [198] RouteAttribute                               OPTIONAL,
    mscOutgoingRouteAttribute           [199] RouteAttribute                               OPTIONAL,
    networkCallReference                [200] NetworkCallReference                         OPTIONAL,
    setupTime                           [201] TimeStamp                                    OPTIONAL,
    alertingTime                        [202] TimeStamp                                    OPTIONAL,
    voiceIndicator                      [203] VoiceIndicator                               OPTIONAL,
    bCategory                           [204] BCategory                                    OPTIONAL,
    callType                            [205] CallType                                     OPTIONAL
}

MOSMSRecord                ::= SET
{
    recordType                                 [0] CallEventRecordType                     OPTIONAL,
    servedIMSI                                 [1] IMSI                                    OPTIONAL,
    servedIMEI                                 [2] IMEI                                    OPTIONAL,
    servedMSISDN                               [3] MSISDN                                  OPTIONAL,
    msClassmark                                [4] Classmark                               OPTIONAL,
    serviceCentre                              [5] AddressString                           OPTIONAL,
    recordingEntity                            [6] RecordingEntity                         OPTIONAL,
    location                                   [7] LocationAreaAndCell                     OPTIONAL,
    messageReference                           [8] MessageReference                        OPTIONAL,
    originationTime                            [9] TimeStamp                               OPTIONAL,
    smsResult                                 [10] SMSResult                               OPTIONAL,
    recordExtensions                          [11] ManagementExtensions                    OPTIONAL,
    destinationNumber                         [12] SmsTpDestinationNumber                  OPTIONAL,
    cAMELSMSInformation                       [13] CAMELSMSInformation                     OPTIONAL,
    systemType                                [14] SystemType                              OPTIONAL,
    basicService                             [130] BasicServiceCode                        OPTIONAL,
    additionalChgInfo                        [133] AdditionalChgInfo                       OPTIONAL,
    classmark3                               [140] Classmark3                              OPTIONAL,
    chargedParty                             [141] ChargedParty                            OPTIONAL,
    orgRNCorBSCId                            [167] RNCorBSCId                              OPTIONAL,
    orgMSCId                                 [168] MSCId                                   OPTIONAL,
    globalAreaID                             [188] GAI                                     OPTIONAL,
    subscriberCategory                       [190] SubscriberCategory                      OPTIONAL,
    firstmccmnc                              [192] MCCMNC                                  OPTIONAL,
    smsUserDataType                          [195] SmsUserDataType                         OPTIONAL,
    smstext                                  [196] SMSTEXT                                 OPTIONAL,
    maximumNumberOfSMSInTheConcatenatedSMS   [197] MaximumNumberOfSMSInTheConcatenatedSMS  OPTIONAL,
    concatenatedSMSReferenceNumber           [198] ConcatenatedSMSReferenceNumber          OPTIONAL,
    sequenceNumberOfTheCurrentSMS            [199] SequenceNumberOfTheCurrentSMS           OPTIONAL,
    hotBillingTag                            [200] HotBillingTag                           OPTIONAL,
    callReference                            [201] CallReference                           OPTIONAL
}

MTSMSRecord                ::= SET
{
    recordType                                [0] CallEventRecordType                      OPTIONAL,
    serviceCentre                             [1] AddressString                            OPTIONAL,
    servedIMSI                                [2] IMSI                                     OPTIONAL,
    servedIMEI                                [3] IMEI                                     OPTIONAL,
    servedMSISDN                              [4] MSISDN                                   OPTIONAL,
    msClassmark                               [5] Classmark                                OPTIONAL,
    recordingEntity                           [6] RecordingEntity                          OPTIONAL,
    location                                  [7] LocationAreaAndCell                      OPTIONAL,
    deliveryTime                              [8] TimeStamp                                OPTIONAL,
    smsResult                                 [9] SMSResult                                OPTIONAL,
    recordExtensions                         [10] ManagementExtensions                     OPTIONAL,
    systemType                               [11] SystemType                               OPTIONAL,
    cAMELSMSInformation                      [12] CAMELSMSInformation                      OPTIONAL,
    basicService                            [130] BasicServiceCode                         OPTIONAL,
    additionalChgInfo                       [133] AdditionalChgInfo                        OPTIONAL,
    classmark3                              [140] Classmark3                               OPTIONAL,
    chargedParty                            [141] ChargedParty                             OPTIONAL,
    orgRNCorBSCId                           [167] RNCorBSCId                               OPTIONAL,
    orgMSCId                                [168] MSCId                                    OPTIONAL,
    globalAreaID                            [188] GAI                                      OPTIONAL,
    subscriberCategory                      [190] SubscriberCategory                       OPTIONAL,
    firstmccmnc                             [192] MCCMNC                                   OPTIONAL,
    smsUserDataType                         [195] SmsUserDataType                          OPTIONAL,
    smstext                                 [196] SMSTEXT                                  OPTIONAL,
    maximumNumberOfSMSInTheConcatenatedSMS  [197] MaximumNumberOfSMSInTheConcatenatedSMS   OPTIONAL,
    concatenatedSMSReferenceNumber          [198] ConcatenatedSMSReferenceNumber           OPTIONAL,
    sequenceNumberOfTheCurrentSMS           [199] SequenceNumberOfTheCurrentSMS            OPTIONAL,
    hotBillingTag                           [200] HotBillingTag                            OPTIONAL,
    origination                             [201] CallingNumber                            OPTIONAL,
    callReference                           [202] CallReference                            OPTIONAL
}

HLRIntRecord            ::= SET
{
    recordType                             [0] CallEventRecordType                         OPTIONAL,
    servedIMSI                             [1] IMSI                                        OPTIONAL,
    servedMSISDN                           [2] MSISDN                                      OPTIONAL,
    recordingEntity                        [3] RecordingEntity                             OPTIONAL,
    basicService                           [4] BasicServiceCode                            OPTIONAL,
    routingNumber                          [5] RoutingNumber                               OPTIONAL,
    interrogationTime                      [6] TimeStamp                                   OPTIONAL,
    numberOfForwarding                     [7] NumberOfForwarding                          OPTIONAL,
    interrogationResult                    [8] HLRIntResult                                OPTIONAL,
    recordExtensions                       [9] ManagementExtensions                        OPTIONAL,
    orgMSCId                             [168] MSCId                                       OPTIONAL,
    callReference                        [169] CallReference                               OPTIONAL
}

SSActionRecord            ::= SET
{
    recordType                             [0] CallEventRecordType                         OPTIONAL,
    servedIMSI                             [1] IMSI                                        OPTIONAL,
    servedIMEI                             [2] IMEI                                        OPTIONAL,
    servedMSISDN                           [3] MSISDN                                      OPTIONAL,
    msClassmark                            [4] Classmark                                   OPTIONAL,
    recordingEntity                        [5] RecordingEntity                             OPTIONAL,
    location                               [6] LocationAreaAndCell                         OPTIONAL,
    basicServices                          [7] BasicServices                               OPTIONAL,
    supplService                           [8] SS-Code                                     OPTIONAL,
    ssAction                               [9] SSActionType                                OPTIONAL,
    ssActionTime                          [10] TimeStamp                                   OPTIONAL,
    ssParameters                          [11] SSParameters                                OPTIONAL,
    ssActionResult                        [12] SSActionResult                              OPTIONAL,
    callReference                         [13] CallReference                               OPTIONAL,
    recordExtensions                      [14] ManagementExtensions                        OPTIONAL,
    systemType                            [15] SystemType                                  OPTIONAL,
    ussdCodingScheme                     [126] UssdCodingScheme                            OPTIONAL,
    ussdString                           [127] SEQUENCE OF UssdString                      OPTIONAL,
    ussdNotifyCounter                    [128] UssdNotifyCounter                           OPTIONAL,
    ussdRequestCounter                   [129] UssdRequestCounter                          OPTIONAL,
    additionalChgInfo                    [133] AdditionalChgInfo                           OPTIONAL,
    classmark3                           [140] Classmark3                                  OPTIONAL,
    chargedParty                         [141] ChargedParty                                OPTIONAL,
    orgRNCorBSCId                        [167] RNCorBSCId                                  OPTIONAL,
    orgMSCId                             [168] MSCId                                       OPTIONAL,
    globalAreaID                         [188] GAI                                         OPTIONAL,
    subscriberCategory                   [190] SubscriberCategory                          OPTIONAL,
    firstmccmnc                          [192] MCCMNC                                      OPTIONAL,
    hotBillingTag                        [200] HotBillingTag                               OPTIONAL
}

CommonEquipRecord         ::= SET
{
    recordType                         [0] CallEventRecordType                             OPTIONAL,
    equipmentType                      [1] EquipmentType                                   OPTIONAL,
    equipmentId                        [2] EquipmentId                                     OPTIONAL,
    servedIMSI                         [3] IMSI                                            OPTIONAL,
    servedMSISDN                       [4] MSISDN                                          OPTIONAL,
    recordingEntity                    [5] RecordingEntity                                 OPTIONAL,
    basicService                       [6] BasicServiceCode                                OPTIONAL,
    changeOfService                    [7] SEQUENCE OF ChangeOfService                     OPTIONAL,
    supplServicesUsed                  [8] SEQUENCE OF SuppServiceUsed                     OPTIONAL,
    seizureTime                        [9] TimeStamp                                       OPTIONAL,
    releaseTime                       [10] TimeStamp                                       OPTIONAL,
    callDuration                      [11] CallDuration                                    OPTIONAL,
    callReference                     [12] CallReference                                   OPTIONAL,
    sequenceNumber                    [13] SequenceNumber                                  OPTIONAL,
    recordExtensions                  [14] ManagementExtensions                            OPTIONAL,
    systemType                        [15] SystemType                                      OPTIONAL,
    rateIndication                    [16] RateIndication                                  OPTIONAL,
    fnur                              [17] Fnur                                            OPTIONAL,
    partialRecordType                 [18] PartialRecordType                               OPTIONAL,
    causeForTerm                     [100] CauseForTerm                                    OPTIONAL,
    diagnostics                      [101] Diagnostics                                     OPTIONAL,
    servedIMEI                       [102] IMEI                                            OPTIONAL,
    additionalChgInfo                [133] AdditionalChgInfo                               OPTIONAL,
    orgRNCorBSCId                    [167] RNCorBSCId                                      OPTIONAL,
    orgMSCId                         [168] MSCId                                           OPTIONAL,
    subscriberCategory               [190] SubscriberCategory                              OPTIONAL,
    hotBillingTag                    [200] HotBillingTag                                   OPTIONAL
}

------------------------------------------------------------------------------
--
--  OBSERVED IMEI TICKETS
--
------------------------------------------------------------------------------

ObservedIMEITicket              ::= SET
{
    servedIMEI                        [0] IMEI,
    imeiStatus                        [1] IMEIStatus,
    servedIMSI                        [2] IMSI,
    servedMSISDN                      [3] MSISDN                       OPTIONAL,
    recordingEntity                   [4] RecordingEntity,
    eventTime                         [5] TimeStamp,
    location                          [6] LocationAreaAndCell,
    imeiCheckEvent                    [7] IMEICheckEvent               OPTIONAL,
    callReference                     [8] CallReference                OPTIONAL,
    recordExtensions                  [9] ManagementExtensions         OPTIONAL,
    orgMSCId                        [168] MSCId                        OPTIONAL
}



------------------------------------------------------------------------------
--
--  LOCATION SERICE TICKETS
--
------------------------------------------------------------------------------

MTLCSRecord                ::= SET
{
    recordType                            [0] CallEventRecordType                 OPTIONAL,
    recordingEntity                       [1] RecordingEntity                     OPTIONAL,
    lcsClientType                         [2] LCSClientType                       OPTIONAL,
    lcsClientIdentity                     [3] LCSClientIdentity                   OPTIONAL,
    servedIMSI                            [4] IMSI                                OPTIONAL,
    servedMSISDN                          [5] MSISDN                              OPTIONAL,
    locationType                          [6] LocationType                        OPTIONAL,
    lcsQos                                [7] LCSQoSInfo                          OPTIONAL,
    lcsPriority                           [8] LCS-Priority                        OPTIONAL,
    mlc-Number                            [9] ISDN-AddressString                  OPTIONAL,
    eventTimeStamp                       [10] TimeStamp                           OPTIONAL,
    measureDuration                      [11] CallDuration                        OPTIONAL,
    notificationToMSUser                 [12] NotificationToMSUser                OPTIONAL,
    privacyOverride                      [13] NULL                                OPTIONAL,
    location                             [14] LocationAreaAndCell                 OPTIONAL,
    locationEstimate                     [15] Ext-GeographicalInformation         OPTIONAL,
    positioningData                      [16] PositioningData                     OPTIONAL,
    lcsCause                             [17] LCSCause                            OPTIONAL,
    diagnostics                          [18] Diagnostics                         OPTIONAL,
    systemType                           [19] SystemType                          OPTIONAL,
    recordExtensions                     [20] ManagementExtensions                OPTIONAL,
    causeForTerm                         [21] CauseForTerm                        OPTIONAL,
    lcsReferenceNumber                  [101] CallReferenceNumber                 OPTIONAL,
    servedIMEI                          [102] IMEI                                OPTIONAL,
    additionalChgInfo                   [133] AdditionalChgInfo                   OPTIONAL,
    chargedParty                        [141] ChargedParty                        OPTIONAL,
    orgRNCorBSCId                       [167] RNCorBSCId                          OPTIONAL,
    orgMSCId                            [168] MSCId                               OPTIONAL,
    globalAreaID                        [188] GAI                                 OPTIONAL,
    subscriberCategory                  [190] SubscriberCategory                  OPTIONAL,
    firstmccmnc                         [192] MCCMNC                              OPTIONAL,
    hotBillingTag                       [200] HotBillingTag                       OPTIONAL,
    callReference                       [201] CallReference                       OPTIONAL
}

MOLCSRecord                ::= SET
{
     recordType                         [0] CallEventRecordType                   OPTIONAL,
     recordingEntity                    [1] RecordingEntity                       OPTIONAL,
     lcsClientType                      [2] LCSClientType                         OPTIONAL,
     lcsClientIdentity                  [3] LCSClientIdentity                     OPTIONAL,
     servedIMSI                         [4] IMSI                                  OPTIONAL,
     servedMSISDN                       [5] MSISDN                                OPTIONAL,
     molr-Type                          [6] MOLR-Type                             OPTIONAL,
     lcsQos                             [7] LCSQoSInfo                            OPTIONAL,
     lcsPriority                        [8] LCS-Priority                          OPTIONAL,
     mlc-Number                         [9] ISDN-AddressString                    OPTIONAL,
     eventTimeStamp                    [10] TimeStamp                             OPTIONAL,
     measureDuration                   [11] CallDuration                          OPTIONAL,
     location                          [12] LocationAreaAndCell                   OPTIONAL,
     locationEstimate                  [13] Ext-GeographicalInformation           OPTIONAL,
     positioningData                   [14] PositioningData                       OPTIONAL,
     lcsCause                          [15] LCSCause                              OPTIONAL,
     diagnostics                       [16] Diagnostics                           OPTIONAL,
     systemType                        [17] SystemType                            OPTIONAL,
     recordExtensions                  [18] ManagementExtensions                  OPTIONAL,
     causeForTerm                      [19] CauseForTerm                          OPTIONAL,
     lcsReferenceNumber               [101] CallReferenceNumber                   OPTIONAL,
     servedIMEI                       [102] IMEI                                  OPTIONAL,
     additionalChgInfo                [133] AdditionalChgInfo                     OPTIONAL,
     chargedParty                     [141] ChargedParty                          OPTIONAL,
     orgRNCorBSCId                    [167] RNCorBSCId                            OPTIONAL,
     orgMSCId                         [168] MSCId                                 OPTIONAL,
     globalAreaID                     [188] GAI                                   OPTIONAL,
     subscriberCategory               [190] SubscriberCategory                    OPTIONAL,
     firstmccmnc                      [192] MCCMNC                                OPTIONAL,
     hotBillingTag                    [200] HotBillingTag                         OPTIONAL,
    callReference                     [201] CallReference                         OPTIONAL
}

NILCSRecord                ::= SET
{
    recordType                        [0] CallEventRecordType                     OPTIONAL,
    recordingEntity                   [1] RecordingEntity                         OPTIONAL,
    lcsClientType                     [2] LCSClientType                           OPTIONAL,
    lcsClientIdentity                 [3] LCSClientIdentity                       OPTIONAL,
    servedIMSI                        [4] IMSI                                    OPTIONAL,
    servedMSISDN                      [5] MSISDN                                  OPTIONAL,
    servedIMEI                        [6] IMEI                                    OPTIONAL,
    emsDigits                         [7] ISDN-AddressString                      OPTIONAL,
    emsKey                            [8] ISDN-AddressString                      OPTIONAL,
    lcsQos                            [9] LCSQoSInfo                              OPTIONAL,
    lcsPriority                      [10] LCS-Priority                            OPTIONAL,
    mlc-Number                       [11] ISDN-AddressString                      OPTIONAL,
    eventTimeStamp                   [12] TimeStamp                               OPTIONAL,
    measureDuration                  [13] CallDuration                            OPTIONAL,
    location                         [14] LocationAreaAndCell                     OPTIONAL,
    locationEstimate                 [15] Ext-GeographicalInformation             OPTIONAL,
    positioningData                  [16] PositioningData                         OPTIONAL,
    lcsCause                         [17] LCSCause                                OPTIONAL,
    diagnostics                      [18] Diagnostics                             OPTIONAL,
    systemType                       [19] SystemType                              OPTIONAL,
    recordExtensions                 [20] ManagementExtensions                    OPTIONAL,
    causeForTerm                     [21] CauseForTerm                            OPTIONAL,
    lcsReferenceNumber              [101] CallReferenceNumber                     OPTIONAL,
    additionalChgInfo               [133] AdditionalChgInfo                       OPTIONAL,
    chargedParty                    [141] ChargedParty                            OPTIONAL,
    orgRNCorBSCId                   [167] RNCorBSCId                              OPTIONAL,
    orgMSCId                        [168] MSCId                                   OPTIONAL,
    globalAreaID                    [188] GAI                                     OPTIONAL,
    subscriberCategory              [190] SubscriberCategory                      OPTIONAL,
    firstmccmnc                     [192] MCCMNC                                  OPTIONAL,
    hotBillingTag                   [200] HotBillingTag                           OPTIONAL,
    callReference                   [201] CallReference                           OPTIONAL
}


------------------------------------------------------------------------------
--
--  FTAM / FTP / TFTP FILE CONTENTS
--
------------------------------------------------------------------------------

CallEventDataFile        ::= SEQUENCE
{
    headerRecord            [0] HeaderRecord,
    callEventRecords        [1] SEQUENCE OF CallEventRecord,
    trailerRecord           [2] TrailerRecord,
    extensions              [3] ManagementExtensions
}

ObservedIMEITicketFile    ::= SEQUENCE
{
    productionDateTime      [0] TimeStamp,
    observedIMEITickets     [1] SEQUENCE OF ObservedIMEITicket,
    noOfRecords             [2] INTEGER,
    extensions              [3] ManagementExtensions
}

HeaderRecord            ::= SEQUENCE
{
    productionDateTime      [0] TimeStamp,
    recordingEntity         [1] RecordingEntity,
    extensions              [2] ManagementExtensions
}

TrailerRecord            ::= SEQUENCE
{
    productionDateTime      [0] TimeStamp,
    recordingEntity         [1] RecordingEntity,
    firstCallDateTime       [2] TimeStamp,
    lastCallDateTime        [3] TimeStamp,
    noOfRecords             [4] INTEGER,
    extensions              [5] ManagementExtensions
}


------------------------------------------------------------------------------
--
--  COMMON DATA TYPES
--
------------------------------------------------------------------------------

AdditionalChgInfo        ::= SEQUENCE
{
    chargeIndicator     [0] ChargeIndicator      OPTIONAL,
    chargeParameters    [1] OCTET STRING         OPTIONAL
}

AddressString ::= OCTET STRING -- (SIZE (1..maxAddressLength))
    -- This type is used to represent a number for addressing
    -- purposes. It is composed of
    --    a)    one octet for nature of address, and numbering plan
    --        indicator.
    --    b)    digits of an address encoded as TBCD-String.

    -- a)    The first octet includes a one bit extension indicator, a
    --        3 bits nature of address indicator and a 4 bits numbering
    --        plan indicator, encoded as follows:

    -- bit 8: 1  (no extension)

    -- bits 765: nature of address indicator
    --    000  unknown
    --    001  international number
    --    010  national significant number
    --    011  network specific number
    --    100  subscriber number
    --    101  reserved
    --    110  abbreviated number
    --    111  reserved for extension

    -- bits 4321: numbering plan indicator
    --    0000  unknown
    --    0001  ISDN/Telephony Numbering Plan (Rec CCITT E.164)
    --    0010  spare
    --    0011  data numbering plan (CCITT Rec X.121)
    --    0100  telex numbering plan (CCITT Rec F.69)
    --    0101  spare
    --    0110  land mobile numbering plan (CCITT Rec E.212)
    --    0111  spare
    --    1000  national numbering plan
    --    1001  private numbering plan
    --    1111  reserved for extension

    --    all other values are reserved.

    -- b)    The following octets representing digits of an address
    --        encoded as a TBCD-STRING.

-- maxAddressLength  INTEGER ::= 20

AiurRequested            ::= ENUMERATED
{
    --
    -- See Bearer Capability TS 24.008
    -- (note that value "4" is intentionally missing
    --  because it is not used in TS 24.008)
    --

    aiur09600BitsPerSecond        (1),
    aiur14400BitsPerSecond        (2),
    aiur19200BitsPerSecond        (3),
    aiur28800BitsPerSecond        (5),
    aiur38400BitsPerSecond        (6),
    aiur43200BitsPerSecond        (7),
    aiur57600BitsPerSecond        (8),
    aiur38400BitsPerSecond1       (9),
    aiur38400BitsPerSecond2       (10),
    aiur38400BitsPerSecond3       (11),
    aiur38400BitsPerSecond4       (12)
}

AOCParameters            ::= SEQUENCE
{
    --
    -- See TS 22.024.
    --
    e1                    [1] EParameter      OPTIONAL,
    e2                    [2] EParameter      OPTIONAL,
    e3                    [3] EParameter      OPTIONAL,
    e4                    [4] EParameter      OPTIONAL,
    e5                    [5] EParameter      OPTIONAL,
    e6                    [6] EParameter      OPTIONAL,
    e7                    [7] EParameter      OPTIONAL
}

AOCParmChange            ::= SEQUENCE
{
    changeTime            [0] TimeStamp,
    newParameters         [1] AOCParameters
}

BasicService                  ::= OCTET STRING -- (SIZE(1))

--This parameter identifies the ISDN Basic service as defined in ETSI specification ETS 300 196.
--     allServices                                      '00'h
--     speech                                           '01'h
--     unrestricteDigtalInfo                            '02'h
--     audio3k1HZ                                       '03'h
--     unrestricteDigtalInfowithtoneandannoucement      '04'h
--     telephony3k1HZ                                   '20'h
--     teletext                                         '21'h
--     telefaxGroup4Class1                              '22'h
--     videotextSyntaxBased                             '23'h
--     videotelephony                                   '24'h
--     telefaxGroup2-3                                  '25'h
--     telephony7kHZ                                    '26'h



BasicServices            ::= SET OF BasicServiceCode

BasicServiceCode ::= CHOICE
{
    bearerService    [2] BearerServiceCode,
    teleservice      [3] TeleserviceCode
}


TeleserviceCode ::= OCTET STRING -- (SIZE (1))
    -- This type is used to represent the code identifying a single
    -- teleservice, a group of teleservices, or all teleservices. The
    -- services are defined in TS GSM 02.03.
    -- The internal structure is defined as follows:

    -- bits 87654321: group (bits 8765) and specific service
    -- (bits 4321)

--    allTeleservices                 (0x00),
--    allSpeechTransmissionServices   (0x10),
--    telephony                       (0x11),
--    emergencyCalls                  (0x12),
--
--    allShortMessageServices         (0x20),
--    shortMessageMT-PP               (0x21),
--    shortMessageMO-PP               (0x22),
--
--    allFacsimileTransmissionServices (0x60),
--    facsimileGroup3AndAlterSpeech    (0x61),
--    automaticFacsimileGroup3         (0x62),
--    facsimileGroup4                  (0x63),
--
--     The following non-hierarchical Compound Teleservice Groups
--     are defined in TS GSM 02.30:
--    allDataTeleservices              (0x70),
--         covers Teleservice Groups 'allFacsimileTransmissionServices'
--         and 'allShortMessageServices'
--    allTeleservices-ExeptSMS         (0x80),
--       covers Teleservice Groups 'allSpeechTransmissionServices' and
--       'allFacsimileTransmissionServices'
--
--    Compound Teleservice Group Codes are only used in call
--    independent supplementary service operations, i.e. they
--    are not used in InsertSubscriberData or in
--    DeleteSubscriberData messages.
--
--    allVoiceGroupCallServices (0x90),
--    voiceGroupCall            (0x91),
--    voiceBroadcastCall        (0x92),
--
--    allPLMN-specificTS        (0xd0),
--    plmn-specificTS-1         (0xd1),
--    plmn-specificTS-2         (0xd2),
--    plmn-specificTS-3         (0xd3),
--    plmn-specificTS-4         (0xd4),
--    plmn-specificTS-5         (0xd5),
--    plmn-specificTS-6         (0xd6),
--    plmn-specificTS-7         (0xd7),
--    plmn-specificTS-8         (0xd8),
--    plmn-specificTS-9         (0xd9),
--    plmn-specificTS-A         (0xda),
--    plmn-specificTS-B         (0xdb),
--    plmn-specificTS-C         (0xdc),
--    plmn-specificTS-D         (0xdd),
--    plmn-specificTS-E         (0xde),
--    plmn-specificTS-F         (0xdf)


BearerServiceCode ::= OCTET STRING -- (SIZE (1))
    -- This type is used to represent the code identifying a single
    -- bearer service, a group of bearer services, or all bearer
    -- services. The services are defined in TS 3GPP TS 22.002 [3].
    -- The internal structure is defined as follows:
    --
    -- plmn-specific bearer services:
    -- bits 87654321: defined by the HPLMN operator

    -- rest of bearer services:
    -- bit 8: 0 (unused)
    -- bits 7654321: group (bits 7654), and rate, if applicable
    -- (bits 321)

--    allBearerServices          (0x00),
--    allDataCDA-Services        (0x10),
--    dataCDA-300bps             (0x11),
--    dataCDA-1200bps            (0x12),
--    dataCDA-1200-75bps         (0x13),
--    dataCDA-2400bps            (0x14),
--    dataCDA-4800bps            (0x15),
--    dataCDA-9600bps            (0x16),
--    general-dataCDA            (0x17),
--
--    allDataCDS-Services        (0x18),
--    dataCDS-1200bps            (0x1a),
--    dataCDS-2400bps            (0x1c),
--    dataCDS-4800bps            (0x1d),
--    dataCDS-9600bps            (0x1e),
--    general-dataCDS            (0x1f),
--
--    allPadAccessCA-Services      (0x20),
--    padAccessCA-300bps           (0x21),
--    padAccessCA-1200bps          (0x22),
--    padAccessCA-1200-75bps       (0x23),
--    padAccessCA-2400bps          (0x24),
--    padAccessCA-4800bps          (0x25),
--    padAccessCA-9600bps          (0x26),
--    general-padAccessCA          (0x27),
--
--    allDataPDS-Services          (0x28),
--    dataPDS-2400bps              (0x2c),
--    dataPDS-4800bps              (0x2d),
--    dataPDS-9600bps              (0x2e),
--    general-dataPDS              (0x2f),
--
--    allAlternateSpeech-DataCDA            (0x30),
--
--    allAlternateSpeech-DataCDS            (0x38),
--
--    allSpeechFollowedByDataCDA            (0x40),
--
--    allSpeechFollowedByDataCDS            (0x48),
--
--     The following non-hierarchical Compound Bearer Service
--     Groups are defined in TS GSM 02.30:
--    allDataCircuitAsynchronous              (0x50),
--         covers "allDataCDA-Services", "allAlternateSpeech-DataCDA" and
--         "allSpeechFollowedByDataCDA"
--    allDataCircuitSynchronous               (0x58),
--         covers "allDataCDS-Services", "allAlternateSpeech-DataCDS" and
--         "allSpeechFollowedByDataCDS"
--    allAsynchronousServices                 (0x60),
--         covers "allDataCDA-Services", "allAlternateSpeech-DataCDA",
--         "allSpeechFollowedByDataCDA" and "allPadAccessCDA-Services"
--    allSynchronousServices                  (0x68),
--        covers "allDataCDS-Services", "allAlternateSpeech-DataCDS",
--        "allSpeechFollowedByDataCDS" and "allDataPDS-Services"
--
--     Compound Bearer Service Group Codes are only used in call
--     independent supplementary service operations, i.e. they
--     are not used in InsertSubscriberData or in
--     DeleteSubscriberData messages.
--
--    allPLMN-specificBS           (0xd0),
--    plmn-specificBS-1            (0xd1),
--    plmn-specificBS-2            (0xd2),
--    plmn-specificBS-3            (0xd3),
--    plmn-specificBS-4            (0xd4),
--    plmn-specificBS-5            (0xd5),
--    plmn-specificBS-6            (0xd6),
--    plmn-specificBS-7            (0xd7),
--    plmn-specificBS-8            (0xd8),
--    plmn-specificBS-9            (0xd9),
--    plmn-specificBS-A            (0xda),
--    plmn-specificBS-B            (0xdb),
--    plmn-specificBS-C            (0xdc),
--    plmn-specificBS-D            (0xdd),
--    plmn-specificBS-E            (0xde),
--    plmn-specificBS-F            (0xdf)


BCDDirectoryNumber        ::= OCTET STRING
    -- This type contains the binary coded decimal representation of
    -- a directory number e.g. calling/called/connected/translated number.
    -- The encoding of the octet string is in accordance with the
    -- the elements "Calling party BCD number", "Called party BCD number"
    -- and "Connected number" defined in TS 24.008.
    -- This encoding includes type of number and number plan information
    -- together with a BCD encoded digit string.
    -- It may also contain both a presentation and screening indicator
    -- (octet 3a).
    -- For the avoidance of doubt, this field does not include
    -- octets 1 and 2, the element name and length, as this would be
    -- redundant.

CallDuration             ::= INTEGER
    --
    -- The call duration in seconds.
    -- For successful calls this is the chargeable duration.
    -- For call attempts this is the call holding time.
    --

CallEventRecordType     ::= ENUMERATED -- INTEGER
{
    moCallRecord          (0),
    mtCallRecord          (1),
    roamingRecord         (2),
    incGatewayRecord      (3),
    outGatewayRecord      (4),
    transitCallRecord     (5),
    moSMSRecord           (6),
    mtSMSRecord           (7),
    ssActionRecord        (10),
    hlrIntRecord          (11),
    commonEquipRecord     (14),
    moTraceRecord         (15),
    mtTraceRecord         (16),
    termCAMELRecord       (17),
    mtLCSRecord           (23),
    moLCSRecord           (24),
    niLCSRecord           (25),
    forwardCallRecord     (100)
}

CalledNumber             ::= BCDDirectoryNumber

CallingNumber            ::= BCDDirectoryNumber

CallingPartyCategory     ::= Category

CallReference            ::= OCTET STRING -- (SIZE (1..8))

CallReferenceNumber ::= OCTET STRING -- (SIZE (1..8))

CAMELDestinationNumber    ::= DestinationRoutingAddress

CAMELInformation        ::= SET
{
    cAMELDestinationNumber      [1] CAMELDestinationNumber       OPTIONAL,
    connectedNumber             [2] ConnectedNumber                  OPTIONAL,
    roamingNumber               [3] RoamingNumber                OPTIONAL,
    mscOutgoingROUTE            [4] ROUTE                        OPTIONAL,
    seizureTime                 [5] TimeStamp                    OPTIONAL,
    answerTime                  [6] TimeStamp                    OPTIONAL,
    releaseTime                 [7] TimeStamp                    OPTIONAL,
    callDuration                [8] CallDuration                 OPTIONAL,
    dataVolume                  [9] DataVolume                   OPTIONAL,
    cAMELInitCFIndicator       [10] CAMELInitCFIndicator         OPTIONAL,
    causeForTerm               [11] CauseForTerm                 OPTIONAL,
    cAMELModification          [12] ChangedParameters            OPTIONAL,
    freeFormatData             [13] FreeFormatData               OPTIONAL,
    diagnostics                [14] Diagnostics                  OPTIONAL,
    freeFormatDataAppend       [15] BOOLEAN                      OPTIONAL,
    freeFormatData-2           [16] FreeFormatData               OPTIONAL,
    freeFormatDataAppend-2     [17] BOOLEAN                      OPTIONAL
}

CAMELSMSInformation        ::= SET
{
    gsm-SCFAddress                [1] Gsm-SCFAddress             OPTIONAL,
    serviceKey                    [2] ServiceKey                 OPTIONAL,
    defaultSMSHandling            [3] DefaultSMS-Handling        OPTIONAL,
    freeFormatData                [4] FreeFormatData             OPTIONAL,
    callingPartyNumber            [5] CallingNumber              OPTIONAL,
    destinationSubscriberNumber   [6] CalledNumber               OPTIONAL,
    cAMELSMSCAddress              [7] AddressString              OPTIONAL,
    smsReferenceNumber            [8] CallReferenceNumber        OPTIONAL
}

CAMELInitCFIndicator    ::= ENUMERATED
{
    noCAMELCallForwarding      (0),
    cAMELCallForwarding        (1)
}

CAMELModificationParameters    ::= SET
    --
    -- The list contains only parameters changed due to CAMEL call
    -- handling.
    --
{
    callingPartyNumber            [0] CallingNumber             OPTIONAL,
    callingPartyCategory          [1] CallingPartyCategory      OPTIONAL,
    originalCalledPartyNumber     [2] OriginalCalledNumber      OPTIONAL,
    genericNumbers                [3] GenericNumbers            OPTIONAL,
    redirectingPartyNumber        [4] RedirectingNumber         OPTIONAL,
    redirectionCounter            [5] NumberOfForwarding        OPTIONAL
}


Category        ::= OCTET STRING -- (SIZE(1))
    --
    -- The internal structure is defined in ITU-T Rec Q.763.
    --see subscribe category

CauseForTerm            ::= ENUMERATED -- INTEGER
    --
    -- Cause codes from 16 up to 31 are defined in TS 32.015 as 'CauseForRecClosing'
    -- (cause for record closing).
    -- There is no direct correlation between these two types.
    -- LCS related causes belong to the MAP error causes acc. TS 29.002.
    --
{
    normalRelease                               (0),
    partialRecord                               (1),
    partialRecordCallReestablishment            (2),
    unsuccessfulCallAttempt                     (3),
    stableCallAbnormalTermination               (4),
    cAMELInitCallRelease                        (5),
    unauthorizedRequestingNetwork               (52),
    unauthorizedLCSClient                       (53),
    positionMethodFailure                       (54),
    unknownOrUnreachableLCSClient               (58)
}

CellId    ::= OCTET STRING -- (SIZE(2))
    --
    -- Coded according to TS 24.008
    --

ChangedParameters        ::= SET
{
    changeFlags         [0] ChangeFlags,
    changeList      [1] CAMELModificationParameters    OPTIONAL
}

ChangeFlags                ::= BIT STRING
--	{
--	     callingPartyNumberModified            (0),
--	     callingPartyCategoryModified          (1),
--	     originalCalledPartyNumberModified     (2),
--	     genericNumbersModified                (3),
--	     redirectingPartyNumberModified        (4),
--	     redirectionCounterModified            (5)
--	}

ChangeOfClassmark         ::= SEQUENCE
{
    classmark             [0] Classmark,
    changeTime            [1] TimeStamp
}

ChangeOfRadioChannel     ::= SEQUENCE
{
    radioChannel         [0] TrafficChannel,
    changeTime           [1] TimeStamp,
    speechVersionUsed    [2] SpeechVersionIdentifier     OPTIONAL
}

ChangeOfService         ::= SEQUENCE
{
    basicService          [0] BasicServiceCode,
    transparencyInd       [1] TransparencyInd      OPTIONAL,
    changeTime            [2] TimeStamp,
    rateIndication        [3] RateIndication       OPTIONAL,
    fnur                  [4] Fnur OPTIONAL
}

ChannelCoding            ::= ENUMERATED
{
    tchF4800             (1),
    tchF9600             (2),
    tchF14400            (3)
}

ChargeIndicator            ::= ENUMERATED -- INTEGER
{
    noIndication        (0),
    noCharge            (1),
    charge              (2)
}

Classmark                ::= OCTET STRING
    --
    -- See Mobile station classmark  2 or 3  TS 24.008
    --

ConnectedNumber           ::= BCDDirectoryNumber

DataVolume                ::= INTEGER
    --
    -- The volume of data transferred in segments of 64 octets.
    --

Day                       ::= INTEGER -- (1..31)

--DayClass                ::= ObjectInstance

--DayClasses              ::= SET OF DayClass

--DayDefinition           ::= SEQUENCE
--{
--    day                 [0] DayOfTheWeek,
--    dayClass            [1] ObjectInstance
--}

--DayDefinitions            ::= SET OF DayDefinition

--DateDefinition            ::= SEQUENCE
--{
--    month                [0] Month,
--    day                  [1] Day,
--    dayClass             [2] ObjectInstance
--}

--DateDefinitions         ::= SET OF DateDefinition

--DayOfTheWeek            ::= ENUMERATED
--{
--    allDays              (0),
--    sunday               (1),
--    monday               (2),
--    tuesday              (3),
--    wednesday            (4),
--    thursday             (5),
--    friday               (6),
--    saturday             (7)
--}

DestinationRoutingAddress    ::= BCDDirectoryNumber

DefaultCallHandling ::= ENUMERATED
{
    continueCall     (0),
    releaseCall      (1)
}
    -- exception handling:
    -- reception of values in range 2-31 shall be treated as "continueCall"
    -- reception of values greater than 31 shall be treated as "releaseCall"

DeferredLocationEventType ::= BIT STRING
--	{
--	    msAvailable            (0)
--	} (SIZE (1..16))

    -- exception handling
    -- a ProvideSubscriberLocation-Arg containing other values than listed above in
    -- DeferredLocationEventType shall be rejected by the receiver with a return error cause of
    -- unexpected data value.

Diagnostics                        ::= CHOICE
{
    gsm0408Cause                [0] INTEGER,
    -- See TS 24.008
    gsm0902MapErrorValue        [1] INTEGER,
    -- Note: The value to be stored here corresponds to
    -- the local values defined in the MAP-Errors and
    -- MAP-DialogueInformation modules, for full details
    -- see TS 29.002.
    ccittQ767Cause              [2] INTEGER,
    -- See ITU-T Q.767
    networkSpecificCause        [3] ManagementExtension,
    -- To be defined by network operator
    manufacturerSpecificCause   [4] ManagementExtension
    -- To be defined by manufacturer
}

DefaultSMS-Handling ::= ENUMERATED
{
    continueTransaction             (0) ,
    releaseTransaction              (1)
}
--    exception handling:
--    reception of values in range 2-31 shall be treated as "continueTransaction"
--    reception of values greater than 31 shall be treated as "releaseTransaction"

--Destinations            ::= SET OF AE-title

EmergencyCallIndEnable    ::= BOOLEAN

EmergencyCallIndication    ::= SEQUENCE
{
    cellId                [0] CellId,
    callerId              [1] IMSIorIMEI
}

EParameter    ::= INTEGER -- (0..1023)
    --
    -- Coded according to  TS 22.024  and TS 24.080
    --

EquipmentId                ::= INTEGER

Ext-GeographicalInformation ::= OCTET STRING -- (SIZE (1..maxExt-GeographicalInformation))
    -- Refers to geographical Information defined in 3G TS 23.032.
    -- This is composed of 1 or more octets with an internal structure according to
    -- 3G TS 23.032
    -- Octet 1: Type of shape, only the following shapes in 3G TS 23.032 are allowed:
    --        (a) Ellipsoid point with uncertainty circle
    --        (b) Ellipsoid point with uncertainty ellipse
    --        (c) Ellipsoid point with altitude and uncertainty ellipsoid
    --        (d) Ellipsoid Arc
    --        (e) Ellipsoid Point
    -- Any other value in octet 1 shall be treated as invalid
    -- Octets 2 to 8 for case (a) - Ellipsoid point with uncertainty circle
    --        Degrees of Latitude                3 octets
    --        Degrees of Longitude               3 octets
    --        Uncertainty code                   1 octet
    -- Octets 2 to 11 for case (b) - Ellipsoid point with uncertainty ellipse:
    --        Degrees of Latitude                3 octets
    --        Degrees of Longitude               3 octets
    --        Uncertainty semi-major axis        1 octet
    --        Uncertainty semi-minor axis        1 octet
    --        Angle of major axis                1 octet
    --        Confidence                         1 octet
    -- Octets 2 to 14 for case (c) - Ellipsoid point with altitude and uncertainty ellipsoid
    --        Degrees of Latitude                3 octets
    --        Degrees of Longitude               3 octets
    --        Altitude                           2 octets
    --        Uncertainty semi-major axis        1 octet
    --        Uncertainty semi-minor axis        1 octet
    --        Angle of major axis                1 octet
    --        Uncertainty altitude               1 octet
    --        Confidence                         1 octet
    -- Octets 2 to 13 for case (d) - Ellipsoid Arc
    --        Degrees of Latitude                3 octets
    --        Degrees of Longitude               3 octets
    --        Inner radius                       2 octets
    --        Uncertainty radius                 1 octet
    --        Offset angle                       1 octet
    --        Included angle                     1 octet
    --        Confidence                         1 octet
    -- Octets 2 to 7 for case (e) - Ellipsoid Point
    --        Degrees of Latitude                3 octets
    --        Degrees of Longitude               3 octets
    --
    -- An Ext-GeographicalInformation parameter comprising more than one octet and
    -- containing any other shape or an incorrect number of octets or coding according
    -- to 3G TS 23.032 shall be treated as invalid data by a receiver.
    --
    -- An Ext-GeographicalInformation parameter comprising one octet shall be discarded
    -- by the receiver if an Add-GeographicalInformation parameter is received
    -- in the same message.
    --
    -- An Ext-GeographicalInformation parameter comprising one octet shall be treated as
    -- invalid data by the receiver if an Add-GeographicalInformation parameter is not
    -- received in the same message.

-- maxExt-GeographicalInformation  INTEGER ::= 20
    -- the maximum length allows for further shapes in 3G TS 23.032 to be included in later
    -- versions of 3G TS 29.002

EquipmentType           ::= ENUMERATED -- INTEGER
{
    conferenceBridge    (0)
}

FileType                ::= ENUMERATED -- INTEGER
{
    callRecords         (1),
    traceRecords        (9),
    observedIMEITicket  (14)
}

Fnur                            ::= ENUMERATED
{
    --
    -- See Bearer Capability TS 24.008
    --
    fnurNotApplicable                   (0),
    fnur9600-BitsPerSecond        (1),
    fnur14400BitsPerSecond        (2),
    fnur19200BitsPerSecond        (3),
    fnur28800BitsPerSecond        (4),
    fnur38400BitsPerSecond        (5),
    fnur48000BitsPerSecond        (6),
    fnur56000BitsPerSecond        (7),
    fnur64000BitsPerSecond        (8),
    fnur33600BitsPerSecond        (9),
    fnur32000BitsPerSecond        (10),
    fnur31200BitsPerSecond        (11)
}

ForwardToNumber         ::= AddressString

FreeFormatData          ::= OCTET STRING -- (SIZE(1..160))
    --
    -- Free formated data as sent in the FCI message
    -- See TS 29.078
    --

GenericNumber            ::= BCDDirectoryNumber

GenericNumbers           ::= SET OF GenericNumber

Gsm-SCFAddress           ::= ISDNAddressString
    --
    -- See TS 29.002
    --

HLRIntResult             ::= Diagnostics

Horizontal-Accuracy      ::= OCTET STRING -- (SIZE (1))
    -- bit 8 = 0
    -- bits 7-1 = 7 bit Uncertainty Code defined in 3G TS 23.032. The horizontal location
    -- error should be less than the error indicated by the uncertainty code with 67%
    -- confidence.

HotBillingTag            ::= ENUMERATED --INTEGER
{
    noHotBilling        (0),
    hotBilling          (1)
}

HSCSDParmsChange        ::= SEQUENCE
{
    changeTime              [0] TimeStamp,
    hSCSDChanAllocated      [1] NumOfHSCSDChanAllocated,
    initiatingParty         [2] InitiatingParty                 OPTIONAL,
    aiurRequested           [3] AiurRequested                   OPTIONAL,
    chanCodingUsed          [4] ChannelCoding,
    hSCSDChanRequested      [5] NumOfHSCSDChanRequested         OPTIONAL
}


IMEI ::= TBCD-STRING -- (SIZE (8))
    --    Refers to International Mobile Station Equipment Identity
    --    and Software Version Number (SVN) defined in TS GSM 03.03.
    --    If the SVN is not present the last octet shall contain the
    --    digit 0 and a filler.
    --    If present the SVN shall be included in the last octet.

IMSI ::= TBCD-STRING -- (SIZE (3..8))
    -- digits of MCC, MNC, MSIN are concatenated in this order.

IMEICheckEvent            ::= ENUMERATED -- INTEGER
{
    mobileOriginatedCall    (0),
    mobileTerminatedCall    (1),
    smsMobileOriginating    (2),
    smsMobileTerminating    (3),
    ssAction                (4),
    locationUpdate          (5)
}

IMEIStatus                ::= ENUMERATED
{
    greyListedMobileEquipment      (0),
    blackListedMobileEquipment     (1),
    nonWhiteListedMobileEquipment  (2)
}

IMSIorIMEI               ::= CHOICE
{
    imsi                [0] IMSI,
    imei                [1] IMEI
}

InitiatingParty           ::= ENUMERATED
{
    network               (0),
    subscriber            (1)
}

ISDN-AddressString ::=     AddressString -- (SIZE (1..maxISDN-AddressLength))
    -- This type is used to represent ISDN numbers.

-- maxISDN-AddressLength  INTEGER ::= 9

LCSCause    ::= OCTET STRING -- (SIZE(1))
    --
    -- See LCS Cause Value, 3GPP TS 49.031
    --

LCS-Priority ::= OCTET STRING -- (SIZE (1))
    -- 0 = highest priority
    -- 1 = normal priority
    -- all other values treated as 1

LCSClientIdentity         ::= SEQUENCE
{
    lcsClientExternalID    [0] LCSClientExternalID        OPTIONAL,
    lcsClientDialedByMS    [1] AddressString              OPTIONAL,
    lcsClientInternalID    [2] LCSClientInternalID        OPTIONAL
}

LCSClientExternalID ::= SEQUENCE
{
    externalAddress        [0] AddressString          OPTIONAL
--  extensionContainer     [1] ExtensionContainer         OPTIONAL
}

LCSClientInternalID ::= ENUMERATED
{
    broadcastService          (0),
    o-andM-HPLMN              (1),
    o-andM-VPLMN              (2),
    anonymousLocation         (3),
    targetMSsubscribedService (4)
}
    -- for a CAMEL phase 3 PLMN operator client, the value targetMSsubscribedService shall be used

LCSClientType ::= ENUMERATED
{
    emergencyServices         (0),
    valueAddedServices        (1),
    plmnOperatorServices      (2),
    lawfulInterceptServices   (3)
}
    --    exception handling:
    --    unrecognized values may be ignored if the LCS client uses the privacy override
    --    otherwise, an unrecognized value shall be treated as unexpected data by a receiver
    --    a return error shall then be returned if received in a MAP invoke

LCSQoSInfo ::= SEQUENCE
{
    horizontal-accuracy             [0] Horizontal-Accuracy      OPTIONAL,
    verticalCoordinateRequest       [1] NULL                     OPTIONAL,
    vertical-accuracy               [2] Vertical-Accuracy        OPTIONAL,
    responseTime                    [3] ResponseTime             OPTIONAL
}

LevelOfCAMELService        ::= BIT STRING
--	{
--	    basic                         (0),
--	    callDurationSupervision       (1),
--	    onlineCharging                (2)
--	}

LocationAreaAndCell        ::= SEQUENCE
{
    locationAreaCode      [0] LocationAreaCode,
    cellIdentifier        [1] CellId
--
-- For 2G the content of the Cell Identifier is defined by the Cell Id
-- refer TS 24.008 and for 3G by the Service Area Code refer TS 25.413.
--

}

LocationAreaCode        ::= OCTET STRING -- (SIZE(2))
    --
    -- See TS 24.008
    --

LocationChange            ::= SEQUENCE
{
    location              [0] LocationAreaAndCell,
    changeTime            [1] TimeStamp
}

Location-info            ::= SEQUENCE
{
    mscNumber             [1] MscNo                    OPTIONAL,
        location-area             [2] LocationAreaCode,
    cell-identification   [3] CellId                   OPTIONAL
}

LocationType ::= SEQUENCE
{
locationEstimateType             [0] LocationEstimateType,
    deferredLocationEventType    [1] DeferredLocationEventType      OPTIONAL
}

LocationEstimateType ::= ENUMERATED
{
    currentLocation                 (0),
    currentOrLastKnownLocation      (1),
    initialLocation                 (2),
    activateDeferredLocation        (3),
    cancelDeferredLocation          (4)
}
    --    exception handling:
    --    a ProvideSubscriberLocation-Arg containing an unrecognized LocationEstimateType
    --    shall be rejected by the receiver with a return error cause of unexpected data value

LocUpdResult            ::= Diagnostics

ManagementExtensions    ::= SET OF ManagementExtension

ManagementExtension ::= SEQUENCE
{
        identifier    OBJECT IDENTIFIER,
        significance       [1] BOOLEAN , -- DEFAULT FALSE,
        information        [2] OCTET STRING
}


MCCMNC    ::= OCTET STRING -- (SIZE(3))
    --
    -- This type contains the mobile country code (MCC) and the mobile
    -- network code (MNC) of a PLMN.
    --

RateIndication             ::= OCTET STRING -- (SIZE(1))

--0     no rate adaption
--1     V.110, I.460/X.30
--2     ITU-T X.31 flag stuffing
--3     V.120
--7     H.223 & H.245
--11    PIAFS


MessageReference         ::= OCTET STRING

Month                    ::= INTEGER -- (1..12)

MOLR-Type                ::= INTEGER
--0            locationEstimate
--1            assistanceData
--2            deCipheringKeys

MSCAddress               ::= AddressString

MscNo                    ::= ISDN-AddressString
    --
    -- See TS 23.003
    --

MSISDN                   ::= ISDN-AddressString
    --
    -- See TS 23.003
    --

MSPowerClasses           ::= SET OF RFPowerCapability

NetworkCallReference     ::= CallReferenceNumber
    -- See TS 29.002
    --

NetworkSpecificCode      ::= INTEGER
    --
    -- To be defined by network operator
    --

NetworkSpecificServices    ::= SET OF NetworkSpecificCode

NotificationToMSUser ::= ENUMERATED
{
    notifyLocationAllowed                          (0),
    notifyAndVerify-LocationAllowedIfNoResponse    (1),
    notifyAndVerify-LocationNotAllowedIfNoResponse (2),
    locationNotAllowed                             (3)
}
    -- exception handling:
    -- At reception of any other value than the ones listed the receiver shall ignore
    -- NotificationToMSUser.

NumberOfForwarding ::= INTEGER -- (1..5)

NumOfHSCSDChanRequested     ::= INTEGER

NumOfHSCSDChanAllocated     ::= INTEGER

ObservedIMEITicketEnable    ::= BOOLEAN

OriginalCalledNumber        ::= BCDDirectoryNumber

OriginDestCombinations      ::= SET OF OriginDestCombination

OriginDestCombination       ::= SEQUENCE
{
    origin                   [0] INTEGER   OPTIONAL,
    destination              [1] INTEGER   OPTIONAL
    --
    -- Note that these values correspond to the contents
    -- of the attributes originId and destinationId
    -- respectively. At least one of the two must be present.
    --
}

PartialRecordTimer       ::= INTEGER

PartialRecordType        ::= ENUMERATED
{
    timeLimit                       (0),
    serviceChange                   (1),
    locationChange                  (2),
    classmarkChange                 (3),
    aocParmChange                   (4),
    radioChannelChange              (5),
    hSCSDParmChange                 (6),
    changeOfCAMELDestination        (7),
    firstHotBill                    (20),
    severalSSOperationBill          (21)
}

PartialRecordTypes        ::= SET OF PartialRecordType

PositioningData           ::= OCTET STRING -- (SIZE(1..33))
    --
    -- See Positioning Data IE (octet 3..n), 3GPP TS 49.031
    --

RadioChannelsRequested    ::= SET OF RadioChanRequested

RadioChanRequested        ::= ENUMERATED
{
    --
    -- See Bearer Capability TS 24.008
    --
    halfRateChannel            (0),
    fullRateChannel            (1),
    dualHalfRatePreferred      (2),
    dualFullRatePreferred      (3)
}

--RecordClassDestination    ::= CHOICE
--{
--    osApplication            [0] AE-title,
--    fileType                 [1] FileType
--}

--RecordClassDestinations   ::= SET OF RecordClassDestination

RecordingEntity         ::= AddressString

RecordingMethod         ::= ENUMERATED
{
    inCallRecord        (0),
    inSSRecord          (1)
}

RedirectingNumber         ::= BCDDirectoryNumber

RedirectingCounter        ::= INTEGER

ResponseTime ::= SEQUENCE
{
    responseTimeCategory    ResponseTimeCategory
}
    --    note: an expandable SEQUENCE simplifies later addition of a numeric response time.

ResponseTimeCategory ::= ENUMERATED
{
    lowdelay          (0),
    delaytolerant     (1)
}
    --    exception handling:
    --    an unrecognized value shall be treated the same as value 1 (delaytolerant)

RFPowerCapability        ::= INTEGER
    --
    -- This field contains the RF power capability of the Mobile station
    -- classmark 1 and 2 of TS 24.008 expressed as an integer.
    --

RoamingNumber            ::= ISDN-AddressString
    --
    -- See TS 23.003
    --

RoutingNumber            ::= CHOICE
{
    roaming              [1] RoamingNumber,
    forwarded            [2] ForwardToNumber
}

Service                  ::= CHOICE
{
    teleservice               [1] TeleserviceCode,
    bearerService             [2] BearerServiceCode,
    supplementaryService      [3] SS-Code,
    networkSpecificService    [4] NetworkSpecificCode
}

ServiceDistanceDependencies    ::= SET OF ServiceDistanceDependency

ServiceDistanceDependency    ::= SEQUENCE
{
        aocService                              [0] INTEGER,
    chargingZone            [1] INTEGER        OPTIONAL
    --
    -- Note that these values correspond to the contents
    -- of the attributes aocServiceId and zoneId
    -- respectively.
    --
}

ServiceKey ::= INTEGER -- (0..2147483647)

SimpleIntegerName            ::= INTEGER

SimpleStringName            ::= GraphicString

SMSResult                    ::= Diagnostics

SmsTpDestinationNumber ::= OCTET STRING
    --
    -- This type contains the binary coded decimal representation of
    -- the SMS address field the encoding of the octet string is in
    -- accordance with the definition of address fields in TS 23.040.
    -- This encoding includes type of number and numbering plan indication
    -- together with the address value range.
    --

SpeechVersionIdentifier    ::= OCTET STRING -- (SIZE(1))
--    see GSM 08.08

--    000 0001    GSM speech full rate version 1
--    001 0001    GSM speech full rate version 2      used for enhanced full rate
--    010 0001    GSM speech full rate version 3     for future use
--    000 0101    GSM speech half rate version 1
--    001 0101    GSM speech half rate version 2     for future use
--    010 0101    GSM speech half rate version 3    for future use

SSActionResult              ::= Diagnostics

SSActionType                ::= ENUMERATED
{
    registration              (0),
    erasure                   (1),
    activation                (2),
    deactivation              (3),
    interrogation             (4),
    invocation                (5),
    passwordRegistration      (6),
    ussdInvocation            (7)
}

-- ussdInvocation          (7) include ussd phase 1,phase 2

--SS Request = SSActionType

SS-Code ::= OCTET STRING -- (SIZE (1))
    -- This type is used to represent the code identifying a single
    -- supplementary service, a group of supplementary services, or
    -- all supplementary services. The services and abbreviations
    -- used are defined in TS 3GPP TS 22.004 [5]. The internal structure is
    -- defined as follows:
    --
    -- bits 87654321: group (bits 8765), and specific service
    -- (bits 4321)  ussd = ff

--    allSS                   (0x00),
--        reserved for possible future use
--        all SS
--
--    allLineIdentificationSS (0x10),
--         reserved for possible future use
--         all line identification SS
--
--    calling-line-identification-presentation                    (0x11),
--         calling line identification presentation
--    calling-line-identification-restriction                     (0x12),
--         calling line identification restriction
--    connected-line-identification-presentation                  (0x13),
--         connected line identification presentation
--    connected-line-identification-restriction                   (0x14),
--        connected line identification restriction
--    malicious-call-identification                               (0x15),
--         reserved for possible future use
--         malicious call identification
--
--    allNameIdentificationSS (0x18),
--        all name identification SS
--    calling-name-presentation                    (0x19),
--         calling name presentation
--
--         SS-Codes '00011010'B, to '00011111'B, are reserved for future
--        NameIdentification Supplementary Service use.
--
--    allForwardingSS       (0x20),
--         all forwarding SS
--    call-forwarding-unconditional                   (0x21),
--        call forwarding unconditional
--    call-deflection                                 (0x24),
--         call deflection
--    allCondForwardingSS                             (0x28),
--        all conditional forwarding SS
--    call-forwarding-on-mobile-subscriber-busy       (0x29),
--        call forwarding on mobile subscriber busy
--    call-forwarding-on-no-reply                     (0x2a),
--        call forwarding on no reply
--    call-forwarding-on-mobile-subscriber-not-reachable                 (0x2b),
--       call forwarding on mobile subscriber not reachable
--
--    allCallOfferingSS     (0x30),
--        reserved for possible future use
--         all call offering SS includes also all forwarding SS
--
--    explicit-call-transfer                   (0x31),
--            explicit call transfer
--    mobile-access-hunting                    (0x32),
--        reserved for possible future use
--         mobile access hunting
--
--    allCallCompletionSS   (0x40),
--        reserved for possible future use
--        all Call completion SS
--
--    call-waiting                    (0x41),
--         call waiting
--    call-hold                       (0x42),
--        call hold
--    completion-of-call-to-busy-subscribers-originating-side                (0x43),
--       completion of call to busy subscribers, originating side
--    completion-of-call-to-busy-subscribers-destination-side                (0x44),
--        completion of call to busy subscribers, destination side
--         this SS-Code is used only in InsertSubscriberData and DeleteSubscriberData
--
--    multicall                    (0x45),
--         multicall
--
--    allMultiPartySS              (0x50),
--         reserved for possible future use
--        all multiparty SS
--
--    multiPTY                     (0x51),
--        multiparty
--
--    allCommunityOfInterest-SS           (0x60),
--        reserved for possible future use
--         all community of interest SS
--    closed-user-group                   (0x61),
--        closed user group
--
--    allChargingSS                               (0x70),
--         reserved for possible future use
--         all charging SS
--    advice-of-charge-information                (0x71),
--        advice of charge information
--    advice-of-charge-charging                   (0x72),
--         advice of charge charging
--
--    allAdditionalInfoTransferSS    (0x80),
--         reserved for possible future use
--         all additional information transfer SS
--    uUS1-user-to-user-signalling                           (0x81),
--       UUS1 user-to-user signalling
--    uUS2-user-to-user-signalling                           (0x82),
--        UUS2 user-to-user signalling
--    uUS3-user-to-user-signalling                           (0x83),
--        UUS3 user-to-user signalling
--
--    allBarringSS           (0x90),
--        all barring SS
--    barringOfOutgoingCalls (0x91),
--         barring of outgoing calls
--    barring-of-all-outgoing-calls                          (0x92),
--         barring of all outgoing calls
--    barring-of-outgoing-international-calls                (0x93),
--         barring of outgoing international calls
--    boicExHC               (0x94),
--         barring of outgoing international calls except those directed
--         to the home PLMN
--    barringOfIncomingCalls (0x99),
--         barring of incoming calls
--    barring-of-all-incoming-calls                          (0x9a),
--         barring of all incoming calls
--    barring-of-incoming-calls-when-roaming-outside-home-PLMN-Country       (0x9b),
--         barring of incoming calls when roaming outside home PLMN
--         Country
--
--    allCallPrioritySS       (0xa0),
--         reserved for possible future use
--         all call priority SS
--    enhanced-Multilevel-Precedence-Pre-emption-EMLPP-service                (0xa1),
--         enhanced Multilevel Precedence Pre-emption 'EMLPP) service
--
--    allLCSPrivacyException (0xb0),
--         all LCS Privacy Exception Classes
--    universal              (0xb1),
--         allow location by any LCS client
--    callrelated            (0xb2),
--         allow location by any value added LCS client to which a call
--         is established from the target MS
--    callunrelated          (0xb3),
--         allow location by designated external value added LCS clients
--    plmnoperator           (0xb4),
--         allow location by designated PLMN operator LCS clients
--
--    allMOLR-SS                  (0xc0),
--         all Mobile Originating Location Request Classes
--    basicSelfLocation           (0xc1),
--         allow an MS to request its own location
--    autonomousSelfLocation      (0xc2),
--         allow an MS to perform self location without interaction
--         with the PLMN for a predetermined period of time
--    transferToThirdParty        (0xc3),
--         allow an MS to request transfer of its location to another LCS client
--
--    allPLMN-specificSS      (0xf0),
--    plmn-specificSS-1       (0xf1),
--    plmn-specificSS-2       (0xf2),
--    plmn-specificSS-3       (0xf3),
--    plmn-specificSS-4       (0xf4),
--    plmn-specificSS-5       (0xf5),
--    plmn-specificSS-6       (0xf6),
--    plmn-specificSS-7       (0xf7),
--    plmn-specificSS-8       (0xf8),
--    plmn-specificSS-9       (0xf9),
--    plmn-specificSS-A       (0xfa),
--    plmn-specificSS-B       (0xfb),
--    plmn-specificSS-C       (0xfc),
--    plmn-specificSS-D       (0xfd),
--    plmn-specificSS-E       (0xfe),
--    ussd                    (0xff)


SSParameters                ::= CHOICE
{
    forwardedToNumber       [0] ForwardToNumber,
    unstructuredData        [1] OCTET STRING
}

SupplServices               ::= SET OF SS-Code

SuppServiceUsed             ::= SEQUENCE
{
    ssCode                  [0] SS-Code         OPTIONAL,
    ssTime                  [1] TimeStamp       OPTIONAL
}

SwitchoverTime              ::= SEQUENCE
{
    hour                    INTEGER , -- (0..23),
    minute                  INTEGER , -- (0..59),
    second                  INTEGER -- (0..59)
}

SystemType  ::= ENUMERATED
    --  "unknown" is not to be used in PS domain.
{
    unknown                (0),
    iuUTRAN                (1),
    gERAN                  (2)
}

TBCD-STRING ::= OCTET STRING
    -- This type (Telephony Binary Coded Decimal String) is used to
    -- represent several digits from 0 through 9, *, #, a, b, c, two
    -- digits per octet, each digit encoded 0000 to 1001 (0 to 9),
    -- 1010 (*), 1011 (#), 1100 (a), 1101 (b) or 1110 (c); 1111 used
    -- as filler when there is an odd number of digits.

    -- bits 8765 of octet n encoding digit 2n
    -- bits 4321 of octet n encoding digit 2(n-1) +1

TariffId                    ::= INTEGER

TariffPeriod                ::= SEQUENCE
{
    switchoverTime            [0] SwitchoverTime,
    tariffId                  [1] INTEGER
    -- Note that the value of tariffId corresponds
    -- to the attribute tariffId.
}

TariffPeriods                 ::= SET OF TariffPeriod

TariffSystemStatus            ::= ENUMERATED
{
    available           (0),    -- available for modification
    checked             (1),    -- "frozen" and checked
    standby             (2),    -- "frozen" awaiting activation
    active              (3)     -- "frozen" and active
}


TimeStamp                    ::= OCTET STRING -- (SIZE(9))
    --
    -- The contents of this field are a compact form of the UTCTime format
    -- containing local time plus an offset to universal time. Binary coded
    -- decimal encoding is employed for the digits to reduce the storage and
    -- transmission overhead
    -- e.g. YYMMDDhhmmssShhmm
    -- where
    -- YY    =    Year 00 to 99        BCD encoded
    -- MM    =    Month 01 to 12       BCD encoded
    -- DD    =    Day 01 to 31         BCD encoded
    -- hh    =    hour 00 to 23        BCD encoded
    -- mm    =    minute 00 to 59      BCD encoded
    -- ss    =    second 00 to 59      BCD encoded
    -- S     =    Sign 0 = "+", "-"    ASCII encoded
    -- hh    =    hour 00 to 23        BCD encoded
    -- mm    =    minute 00 to 59      BCD encoded
    --

TrafficChannel          ::=    ENUMERATED
{
    fullRate            (0),
    halfRate            (1)
}

TranslatedNumber        ::=     BCDDirectoryNumber

TransparencyInd         ::=    ENUMERATED
{
    transparent         (0),
    nonTransparent      (1)
}

ROUTE                   ::=     CHOICE
{
    rOUTENumber         [0] INTEGER,
    rOUTEName           [1] GraphicString
}

--rOUTEName  1  10 octet

TSChangeover            ::=    SEQUENCE
{
    newActiveTS            [0] INTEGER,
    newStandbyTS           [1] INTEGER,
--    changeoverTime       [2] GeneralizedTime   OPTIONAL,
    authkey                [3] OCTET STRING      OPTIONAL,
    checksum               [4] OCTET STRING      OPTIONAL,
    versionNumber          [5] OCTET STRING      OPTIONAL
    -- Note that if the changeover time is not
    -- specified then the change is immediate.
}

TSCheckError            ::=    SEQUENCE
{
    errorId               [0] TSCheckErrorId
    --fail                [1] ANY DEFINED BY errorId      OPTIONAL
}

TSCheckErrorId          ::=    CHOICE
{
    globalForm            [0] OBJECT IDENTIFIER,
    localForm             [1] INTEGER
}

TSCheckResult           ::=    CHOICE
{
    success             [0] NULL,
    fail                [1] SET OF TSCheckError
}

TSCopyTariffSystem       ::=    SEQUENCE
{
    oldTS                [0] INTEGER,
    newTS                [1] INTEGER
}

TSNextChange            ::=    CHOICE
{
    noChangeover        [0] NULL,
    tsChangeover        [1] TSChangeover
}

TypeOfSubscribers       ::= ENUMERATED
{
    home                (0),    -- HPLMN subscribers
    visiting            (1),    -- roaming subscribers
    all                 (2)
}

TypeOfTransaction       ::=    ENUMERATED
{
    successful          (0),
    unsuccessful        (1),
    all                 (2)
}

Vertical-Accuracy ::= OCTET STRING -- (SIZE (1))
    -- bit 8 = 0
    -- bits 7-1 = 7 bit Vertical Uncertainty Code defined in 3G TS 23.032.
    -- The vertical location error should be less than the error indicated
    -- by the uncertainty code with 67% confidence.

ISDNAddressString ::= AddressString

EmlppPriority ::= OCTET STRING -- (SIZE (1))

--priorityLevelA    EMLPP-Priority ::= 6
--priorityLevelB    EMLPP-Priority ::= 5
--priorityLevel0    EMLPP-Priority ::= 0
--priorityLevel1    EMLPP-Priority ::= 1
--priorityLevel2    EMLPP-Priority ::= 2
--priorityLevel3    EMLPP-Priority ::= 3
--priorityLevel4    EMLPP-Priority ::= 4
--See 29.002


EASubscriberInfo ::= OCTET STRING -- (SIZE (3))
        -- The internal structure is defined by the Carrier Identification
    -- parameter in ANSI T1.113.3. Carrier codes between "000" and "999" may
    -- be encoded as 3 digits using "000" to "999" or as 4 digits using
    -- "0000" to "0999". Carrier codes between "1000" and "9999" are encoded
    -- using 4 digits.

SelectedCIC ::= OCTET STRING -- (SIZE (3))

PortedFlag       ::=    ENUMERATED
{
    numberNotPorted        (0),
    numberPorted           (1)
}

SubscriberCategory   ::= OCTET STRING -- (SIZE (1))
-- unknownuser   = 0x00,
-- frenchuser    = 0x01,
-- englishuser   = 0x02,
-- germanuser    = 0x03,
-- russianuser   = 0x04,
-- spanishuser   = 0x05,
-- specialuser   = 0x06,
-- reserveuser   = 0x09,
-- commonuser    = 0x0a,
-- superioruser  = 0x0b,
-- datacalluser  = 0x0c,
-- testcalluser  = 0x0d,
-- spareuser     = 0x0e,
-- payphoneuser  = 0x0f,
-- coinuser      = 0x20,
-- isup224       = 0xe0


CUGOutgoingAccessIndicator ::=    ENUMERATED
{
    notCUGCall  (0),
    cUGCall     (1)
}

CUGInterlockCode ::= OCTET STRING -- (SIZE (4))

--

CUGOutgoingAccessUsed ::= ENUMERATED
{
    callInTheSameCUGGroup      (0),
    callNotInTheSameCUGGroup   (1)
}

SMSTEXT        ::= OCTET STRING

MSCCIC         ::= INTEGER -- (0..65535)

RNCorBSCId     ::= OCTET STRING -- (SIZE (3))
--octet order is the same as RANAP/BSSAP signaling
--if spc is coded as 14bit, then OCTET STRING1 will filled with 00 ,for example rnc id = 123 will be coded as 00 01 23
--OCTET STRING1
--OCTET STRING2
--OCTET STRING3

MSCId          ::= OCTET STRING -- (SIZE (3))
--National network format , octet order is the same as ISUP signaling
--if spc is coded as 14bit, then OCTET STRING1 will filled with 00,,for example rnc id = 123 will be coded as 00 01 23
--OCTET STRING1
--OCTET STRING2
--OCTET STRING3

EmergencyCallFlag ::= ENUMERATED
{
    notEmergencyCall  (0),
    emergencyCall     (1)
}

CUGIncomingAccessUsed ::= ENUMERATED
{
    callInTheSameCUGGroup      (0),
    callNotInTheSameCUGGroup   (1)
}

SmsUserDataType               ::= OCTET STRING -- (SIZE (1))
--
--00  concatenated-short-messages-8-bit-reference-number
--01  special-sms-message-indication
--02  reserved
--03  Value not used to avoid misinterpretation as <LF>
--04  characterapplication-port-addressing-scheme-8-bit-address
--05  application-port-addressing-scheme-16-bit-address
--06  smsc-control-parameters
--07  udh-source-indicator
--08  concatenated-short-message-16-bit-reference-number
--09  wireless-control-message-protocol
--0A  text-formatting
--0B  predefined-sound
--0C  user-defined-sound-imelody-max-128-bytes
--0D  predefined-animation
--0E  large-animation-16-16-times-4-32-4-128-bytes
--0F  small-animation-8-8-times-4-8-4-32-bytes
--10  large-picture-32-32-128-bytes
--11  small-picture-16-16-32-bytes
--12  variable-picture
--13  User prompt indicator
--14  Extended Object
--15  Reused Extended Object
--16  Compression Control
--17  Object Distribution Indicator
--18  Standard WVG object
--19  Character Size WVG object
--1A  Extended Object Data Request Command
--1B-1F    Reserved for future EMS features (see subclause 3.10)
--20    RFC 822 E-Mail Header
--21    Hyperlink format element
--22    Reply Address Element
--23 - 6F    Reserved for future use
--70 - 7F    (U)SIM Toolkit Security Headers
--80 - 9F    SME to SME specific use
--A0 - BF    Reserved for future use
--C0 - DF    SC specific use
--E0 - FE    Reserved for future use
--FF          normal SMS

ConcatenatedSMSReferenceNumber              ::=  INTEGER -- (0..65535)

MaximumNumberOfSMSInTheConcatenatedSMS      ::=  INTEGER -- (0..255)

SequenceNumberOfTheCurrentSMS               ::=  INTEGER -- (0..255)

SequenceNumber       ::=  INTEGER

--(1...   )
--

DisconnectParty             ::= ENUMERATED
{
      callingPartyRelease           (0),
      calledPartyRelease            (1),
      networkRelease                (2)
}

ChargedParty     ::= ENUMERATED
{
      callingParty           (0),
      calledParty            (1)
}

ChargeAreaCode                      ::=  OCTET STRING -- (SIZE (1..3))

CUGIndex                            ::=  OCTET STRING -- (SIZE (2))

GuaranteedBitRate                   ::= ENUMERATED
{
     gBR14400BitsPerSecond (1),        -- BS20 non-transparent
     gBR28800BitsPerSecond (2),        -- BS20 non-transparent and transparent,
                                      -- BS30 transparent and multimedia
     gBR32000BitsPerSecond (3),        -- BS30 multimedia
     gBR33600BitsPerSecond (4),        -- BS30 multimedia
     gBR56000BitsPerSecond (5),        -- BS30 transparent and multimedia
     gBR57600BitsPerSecond (6),        -- BS20 non-transparent
     gBR64000BitsPerSecond (7),        -- BS30 transparent and multimedia

     gBR12200BitsPerSecond (106),      -- AMR speech
     gBR10200BitsPerSecond (107),      -- AMR speech
     gBR7950BitsPerSecond (108),        -- AMR speech
     gBR7400BitsPerSecond (109),        -- AMR speech
     gBR6700BitsPerSecond (110),        -- AMR speech
     gBR5900BitsPerSecond (111),        -- AMR speech
     gBR5150BitsPerSecond (112),        -- AMR speech
     gBR4750BitsPerSecond (113)         -- AMR speech
}

MaximumBitRate                  ::= ENUMERATED
{
     mBR14400BitsPerSecond (1),         -- BS20 non-transparent
     mBR28800BitsPerSecond (2),         -- BS20 non-transparent and transparent,
                                 -- BS30 transparent and multimedia
     mBR32000BitsPerSecond (3),         -- BS30 multimedia
     mBR33600BitsPerSecond (4),         -- BS30 multimedia
     mBR56000BitsPerSecond (5),         -- BS30 transparent and multimedia
     mBR57600BitsPerSecond (6),         -- BS20 non-transparent
     mBR64000BitsPerSecond (7),         -- BS30 transparent and multimedia

     mBR12200BitsPerSecond (106),      -- AMR speech
     mBR10200BitsPerSecond (107),      -- AMR speech
     mBR7950BitsPerSecond (108),        -- AMR speech
     mBR7400BitsPerSecond (109),        -- AMR speech
     mBR6700BitsPerSecond (110),        -- AMR speech
     mBR5900BitsPerSecond (111),        -- AMR speech
     mBR5150BitsPerSecond (112),        -- AMR speech
     mBR4750BitsPerSecond (113)         -- AMR speech
}


HLC          ::= OCTET STRING

-- this parameter is a 1:1 copy of the contents (i.e. starting with octet 3) of the "high layer compatibility" parameter of ITU-T Q.931 [35].

LLC          ::= OCTET STRING

-- this parameter is a 1:1 copy of the contents (i.e. starting with octet 3) of the "low layer compatibility" parameter of ITU-T Q.931 [35].


ISDN-BC      ::= OCTET STRING

-- this parameter is a 1:1 copy of the contents (i.e. starting with octet 3) of the "bearer capability" parameter of ITU-T Q.931 [35].

ModemType           ::= ENUMERATED
{
    none-modem                  (0),
    modem-v21                   (1),
    modem-v22                   (2),
    modem-v22-bis               (3),
    modem-v23                   (4),
    modem-v26-ter               (5),
    modem-v32                   (6),
    modem-undef-interface       (7),
    modem-autobauding1          (8),
    no-other-modem-type        (31),
    modem-v34                  (33)
}

UssdCodingScheme            ::= OCTET STRING

UssdString                  ::= OCTET STRING

UssdNotifyCounter           ::=  INTEGER -- (0..255)

UssdRequestCounter          ::=  INTEGER -- (0..255)

Classmark3                  ::= OCTET STRING -- (SIZE(2))

OptimalRoutingDestAddress   ::= BCDDirectoryNumber

GAI                         ::= OCTET STRING -- (SIZE(7))
--such as 64 F0 00 00 ABCD 1234

ChangeOfglobalAreaID        ::= SEQUENCE
{
    location                [0] GAI,
    changeTime              [1] TimeStamp
}

InteractionWithIP  ::=  NULL

RouteAttribute     ::=  ENUMERATED
{
    cas    (0),
    tup    (1),
    isup   (2),
    pra    (3),
    bicc   (4),
    sip    (5),
    others (255)
}

VoiceIndicator  ::=    ENUMERATED
{
    sendToneByLocalMsc (0) ,
    sendToneByOtherMsc (1),
    voiceNoIndication  (3)
}

BCategory  ::=    ENUMERATED
{
    subscriberFree         (0),
    subscriberBusy         (1),
    subscriberNoIndication (3)
}

CallType   ::=    ENUMERATED
{
     unknown     (0),
     internal    (1),
     incoming    (2),
     outgoing    (3),
     tandem      (4)
}

-- END
END
}

1;

