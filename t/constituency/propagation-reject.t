#!/usr/bin/perl

use strict;
use warnings;

use Test::More skip_all => 'constituencies being rebuilt';
use RT::IR::Test tests => undef;

use_ok('RT::IR');
RT->Config->Set('RTIR_StrictConstituencyLinking'=> 1);

for my $constituency ('EDUNET','GOVNET') {
    my $path = RT::Plugin->new( name => 'RT::IR' )->Path( 'bin' ) . "/add_constituency";
    diag("running $path to set up EDUNET and GOVNET constituencies");

        my ($exit_code, $output) = RT::Test->run_and_capture(
                command     => $path,
                name        => $constituency,
                force       => 1,
                quiet       => 1,
            );
         ok(!$exit_code, "created constituency $constituency");
         diag "output: $output";

}
my $cf;
diag "load the field" if $ENV{'TEST_VERBOSE'};
{
    my $cfs = RT::CustomFields->new( $RT::SystemUser );
    $cfs->Limit( FIELD => 'Name', VALUE => 'RTIR Constituency', CASESENSITIVE => 0 );
    $cf = $cfs->First;
    ok $cf, 'have a field';
    ok $cf->id, 'with some ID';
}

RT::Test->started_ok;
my $rtir_user = rtir_user();
my $agent = default_agent();

diag "create an IR with GOVNET constituency and create a new "
    . "incident for the IR, we want it to inherit by default"
        if $ENV{'TEST_VERBOSE'};
{
    my $ir_id = $agent->create_rtir_ticket_ok(
        'Incident Reports - GOVNET',
        { Subject => "test" },
    );
    ok $ir_id, "created IR #$ir_id";
    $agent->display_ticket( $ir_id);

    my $inc_id = $agent->create_incident_for_ir(
        $ir_id, { Subject => "test" },
    );

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load( $inc_id );
    ok $ticket->id, 'loaded ticket';
    is $ticket->QueueObj->Name,
        'Incidents - GOVNET', 'correct value';
}

diag "create an IR and check that we couldn't change constituency"
    ." value during creation of new linked incident" if $ENV{'TEST_VERBOSE'};
{
    # create an IR
    my $ir_id = $agent->create_rtir_ticket_ok('Incident Reports - GOVNET',
        { Subject => "test" },
    );
    ok $ir_id, "created ticket #$ir_id";
    $agent->display_ticket( $ir_id);
    $agent->content_like( qr/GOVNET/, "value on the page" );
    my $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load( $ir_id );
    ok $ticket->id, 'loaded ticket';
    is $ticket->QueueObj->Name, 'Incident Reports - GOVNET', 'correct value';

    # click [new] near 'incident', set another constituency and create
    $agent->follow_link_ok({text => 'New'}, "go to 'New Incident' page");
    my $form = $agent->form_number(3);
    $agent->click('CreateIncident');
    is $agent->status, 200, "Attempted to create the ticket";

    DBIx::SearchBuilder::Record::Cachable::FlushCache();

    # Incident has the same value 
    my $inc_id = $agent->get_ticket_id( );
    $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load( $inc_id );
    ok $ticket->id, 'loaded ticket';
    is $ticket->QueueObj->Name, 'Incidents - GOVNET', 'correct value';

    # And the report too
    $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load( $ir_id );
    ok $ticket->id, 'loaded ticket';
    is $ticket->QueueObj->Name, 'Incident Reports - GOVNET', 'correct value';
}

diag "create an incident with EDUNET, then try to create children using"
    ." Incident input field and different constituency. Should be rejected."
        if $ENV{'TEST_VERBOSE'};
{
    my $incident_id = $agent->create_rtir_ticket_ok(
        'Incidents - EDUNET',
        { Subject => "test" },
    );
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $incident_id );
        ok $ticket->id, 'loaded ticket';
        is $ticket->QueueObj->Name, 'Incidents - EDUNET',
            'correct value';
    }

    foreach my $queue( 'Incident Reports', 'Investigations', 'Countermeasures' ) {
        diag "create a ticket in the '$queue - GOVNET' queue" if $ENV{'TEST_VERBOSE'};

        my $id = $agent->create_rtir_ticket(
            $queue. ' - GOVNET',
            {
                Subject => "test constituency",
            },
        );
        ok !$id, 'ticket was not created';
        $agent->content_like(
            qr/choose the same value for a new ticket or use another Incident/mi,
            'creation rejected because of not matching constituency'
        );
    }
}

diag "create an incident with EDUNET and check that we can create children"
    . " with the same constituency and operation is not rejected"
        if $ENV{'TEST_VERBOSE'};
{
    my $incident_id = $agent->create_rtir_ticket_ok(
        'Incidents - EDUNET',
        { Subject => "test" },
    );
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $incident_id );
        ok $ticket->id, 'loaded ticket';
        is $ticket->QueueObj->Name ,
            'Incidents - EDUNET', 'correct value';
    }

    foreach my $queue( 'Incident Reports', 'Investigations', 'Countermeasures' ) {
        diag "create a ticket in the '$queue - EDUNET' queue" if $ENV{'TEST_VERBOSE'};

        my $id = $agent->create_rtir_ticket_ok(
            $queue . ' - EDUNET',
            {
                Subject => "test constituency",
                Incident => $incident_id,
            },
        );

        $agent->display_ticket( $id);
        DBIx::SearchBuilder::Record::Cachable::FlushCache();
        
        {
            my $ticket = RT::Ticket->new( $RT::SystemUser );
            $ticket->Load( $id );
            ok $ticket->id, 'loaded ticket';
            is uc $ticket->QueueObj->FirstCustomFieldValue('RTIR Constituency'),
                'EDUNET', 'correct value';
        } {
            my $ticket = RT::Ticket->new( $RT::SystemUser );
            $ticket->Load( $incident_id );
            ok $ticket->id, 'loaded ticket';
            is $ticket->QueueObj->FirstCustomFieldValue('RTIR Constituency'),
                'EDUNET', 'incident still has the same value';
        }
        $agent->ticket_is_linked_to_inc( $id, $incident_id);
    }
}

diag "create an IR create an Incident with different constituency"
    ." and goto [Link] IR, we shouldn't see an IR there"
        if $ENV{'TEST_VERBOSE'};
{
    # an IR
    my $ir_id = $agent->create_rtir_ticket_ok(
        'Incident Reports - GOVNET',
        { Subject => "test" }
    );
    $agent->display_ticket( $ir_id);
    $agent->content_like( qr/GOVNET/, "value on the page" );
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $ir_id );
        ok $ticket->id, 'loaded ticket';
        is $ticket->QueueObj->Name, 'Incident Reports - GOVNET', 'correct value';
        is $ticket->QueueObj->FirstCustomFieldValue('RTIR Constituency'),
            'GOVNET', 'correct value';
        $ticket->Subject("incident report #$ir_id");
    }

    # an IR
    my $inc_id = $agent->create_rtir_ticket_ok('Incidents - EDUNET',
        { Subject => "test" }, 
    );
    $agent->display_ticket( $inc_id);
    $agent->content_like( qr/EDUNET/, "value on the page" );
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $inc_id );
        ok $ticket->id, 'loaded ticket';
        is $ticket->QueueObj->Name, 'Incidents - EDUNET', 'correct value';
        is $ticket->QueueObj->FirstCustomFieldValue('RTIR Constituency'),
            'EDUNET', 'correct value';
    }
    $agent->get_ok(
        $agent->rt_base_url ."/RTIR/Link/ToIncident/?id=$inc_id&"
        ."Lifecycle=incident_report&Query=id%3D$ir_id"
    );
    $agent->content_unlike(qr/incident report #$ir_id/, 'no IR on the page');
}


diag "check that we can change constituency of an unlinked ticket using 'Edit' page"
    if $ENV{'TEST_VERBOSE'};
{
    # blocks are always linked to an incident
    foreach my $queue( 'Incidents', 'Incident Reports', 'Investigations' ) {
        my $id = $agent->create_rtir_ticket_ok(
            $queue .' - GOVNET',
            { Subject => "test constituency" },
        );
        DBIx::SearchBuilder::Record::Cachable::FlushCache();

        {
            my $ticket = RT::Ticket->new( $RT::SystemUser );
            $ticket->Load( $id );
            ok $ticket->id, 'loaded ticket';
            is $ticket->QueueObj->FirstCustomFieldValue('RTIR Constituency'),
                'GOVNET', 'correct value';
        }
        
        $agent->display_ticket( $id);
        $agent->follow_link( text => 'Edit' );
        $agent->form_number(3);
        $agent->select("Object-RT::Ticket-$id-CustomField-". $cf->id ."-Values" => 'EDUNET' );
        $agent->click('SaveChanges');
        $agent->content_like(qr/Constituency .* changed to EDUNET/mi, 'field is changed');
        DBIx::SearchBuilder::Record::Cachable::FlushCache();

        {
            my $ticket = RT::Ticket->new( $RT::SystemUser );
            $ticket->Load( $id );
            ok $ticket->id, 'loaded ticket';
            is uc $ticket->QueueObj->FirstCustomFieldValue('RTIR Constituency'),
                'EDUNET', 'correct value';
        }
    }
}

diag "check that we can change constituency of an unlinked ticket using 'Edit' page"
    if $ENV{'TEST_VERBOSE'};
{
    my $incident_id = $agent->create_rtir_ticket_ok(
        'Incidents - EDUNET',
        { Subject => "test" },
    );
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $incident_id );
        ok $ticket->id, 'loaded ticket';
        is $ticket->QueueObj->FirstCustomFieldValue('RTIR Constituency'),
            'EDUNET', 'correct value';
    }

    foreach my $queue( 'Countermeasures', 'Incident Reports', 'Investigations' ) {
        my $id = $agent->create_rtir_ticket_ok(
            $queue." - EDUNET",
            {
                Subject => "test constituency",
                Incident => $incident_id,
            },
        );
        DBIx::SearchBuilder::Record::Cachable::FlushCache();
        {
            my $ticket = RT::Ticket->new( $RT::SystemUser );
            $ticket->Load( $id );
            ok $ticket->id, 'loaded ticket';
            is $ticket->QueueObj->FirstCustomFieldValue('RTIR Constituency'),
                'EDUNET', 'correct value';
        }
        
        $agent->display_ticket( $id);
        $agent->follow_link( text => 'Edit' );
        my $form = $agent->form_number(3);
        ok !eval { $form->value('Constituency') }, 'no constituency hidden field';
        ok !$form->find_input( "Object-RT::Ticket-$id-CustomField-". $cf->id ."-Values" ),
            'no constituency select box';
    }

    # check incident as it's linked now
    $agent->display_ticket( $incident_id);
    $agent->follow_link( text => 'Edit' );
    my $form = $agent->form_number(3);
    ok !eval { $form->value('Constituency') }, 'no constituency hidden field';
    ok !$form->find_input( "Object-RT::Ticket-$incident_id-CustomField-". $cf->id ."-Values" ),
        'no constituency select box';
}


undef $agent;
done_testing;
