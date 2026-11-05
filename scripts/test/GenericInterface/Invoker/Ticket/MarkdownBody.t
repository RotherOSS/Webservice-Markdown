# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use v5.24;
use strict;
use warnings;
use utf8;

# core modules

# CPAN modules
use Test2::V0;

# OTOBO modules
use Kernel::System::UnitTest::RegisterOM;    # Set up $Kernel::OM
use Kernel::GenericInterface::Debugger ();
use Kernel::GenericInterface::Invoker  ();
use Kernel::System::VariableCheck      qw(:all);

# This test checks the invoker option ConvertArticleBodyToMarkdown of the package Webservice-Markdown.

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);

my $HelperObject = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $RandomID     = $HelperObject->GetRandomID();

skip_all('HTML::TreeBuilder is not installed') unless $Kernel::OM->Get('Kernel::System::Markdown')->IsAvailable( Direction => 'FromHTML' );

my $TicketObject         = $Kernel::OM->Get('Kernel::System::Ticket');
my $ArticleBackendObject = $Kernel::OM->Get('Kernel::System::Ticket::Article::Backend::Internal');
my $WebserviceObject     = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');

# Only a few article fields are requested, so that the expected results stay small.
my @RequestArticleFields = qw(Body Charset ContentType MimeType Subject);

my $WebserviceID = $WebserviceObject->WebserviceAdd(
    Name   => 'WebserviceMarkdown-' . $RandomID,
    Config => {
        Name        => 'WebserviceMarkdown-' . $RandomID,
        Description => '',
        Debugger    => {
            DebugThreshold => 'debug',
        },
        Requester => {
            Transport => {
                Type   => 'HTTP::REST',
                Config => {
                    Host => '',
                },
            },
            Invoker => {

                # this invoker converts the article body
                MarkdownInvoker => {
                    Type                         => 'Ticket::TicketCreate',
                    ConvertArticleBodyToMarkdown => 1,
                    RequestArticleFields         => \@RequestArticleFields,
                    RequestTicketFields          => ['Title'],
                    RequestDynamicFieldsArticle  => [],
                    RequestDynamicFieldsTicket   => [],
                },

                # this invoker leaves the article body as it is
                PlainInvoker => {
                    Type                        => 'Ticket::TicketUpdate',
                    RequestArticleFields        => \@RequestArticleFields,
                    RequestTicketFields         => ['Title'],
                    RequestDynamicFieldsArticle => [],
                    RequestDynamicFieldsTicket  => [],
                },
            },
        },
    },
    ValidID => 1,
    UserID  => 1,
);
ok( $WebserviceID, 'web service created' );

my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
    DebuggerConfig => {
        DebugThreshold => 'debug',
        TestMode       => 1,
    },
    WebserviceID      => $WebserviceID,
    CommunicationType => 'Requester',
);

my $TicketID = $TicketObject->TicketCreate(
    Title        => 'Markdown test ticket ' . $RandomID,
    Queue        => 'Raw',
    Lock         => 'unlock',
    Priority     => '3 normal',
    State        => 'open',
    CustomerUser => 'customer@example.com',
    OwnerID      => 1,
    UserID       => 1,
);
ok( $TicketID, 'ticket created' );

my $HTMLBody = '<p>Hello <strong>world</strong>, see <a href="https://otobo.io/">OTOBO</a>.</p><ul><li>one</li><li>two</li></ul>';

my $HTMLArticleID = $ArticleBackendObject->ArticleCreate(
    TicketID             => $TicketID,
    IsVisibleForCustomer => 0,
    SenderType           => 'agent',
    From                 => 'Agent <agent@example.com>',
    Subject              => 'HTML article',
    Body                 => $HTMLBody,
    MimeType             => 'text/html',
    Charset              => 'utf-8',
    HistoryType          => 'AddNote',
    HistoryComment       => 'Markdown test',
    UserID               => 1,
);
ok( $HTMLArticleID, 'HTML article created' );

# OTOBO stores the body of an HTML article as plain text and keeps the HTML as attachment 'file-2'.
my %HTMLArticle = $ArticleBackendObject->ArticleGet(
    TicketID  => $TicketID,
    ArticleID => $HTMLArticleID,
    UserID    => 1,
);
is( $HTMLArticle{MimeType}, 'text/plain', 'stored MIME type of the HTML article is text/plain' );

my $PlainArticleID = $ArticleBackendObject->ArticleCreate(
    TicketID             => $TicketID,
    IsVisibleForCustomer => 0,
    SenderType           => 'agent',
    From                 => 'Agent <agent@example.com>',
    Subject              => 'plain article',
    Body                 => "Hello *world*\n- one",
    MimeType             => 'text/plain',
    Charset              => 'utf-8',
    HistoryType          => 'AddNote',
    HistoryComment       => 'Markdown test',
    UserID               => 1,
);
ok( $PlainArticleID, 'plain text article created' );

my @Tests = (
    {
        Name        => 'HTML article is converted to Markdown',
        Invoker     => 'MarkdownInvoker',
        InvokerType => 'Ticket::TicketCreate',
        ArticleID   => $HTMLArticleID,
        Expected    => {
            Body        => "Hello **world**, see [OTOBO](https://otobo.io/).\n\n- one\n- two\n",
            Charset     => 'utf8',
            ContentType => 'text/markdown; charset=utf8',
            MimeType    => 'text/markdown',
            Subject     => 'HTML article',
        },
    },
    {
        Name        => 'plain text article is not converted',
        Invoker     => 'MarkdownInvoker',
        InvokerType => 'Ticket::TicketCreate',
        ArticleID   => $PlainArticleID,
        Expected    => {
            Body        => "Hello *world*\n- one",
            Charset     => 'utf8',
            ContentType => 'text/plain; charset=utf8',
            MimeType    => 'text/plain',
            Subject     => 'plain article',
        },
    },
    {
        Name        => 'HTML article is not converted without the option',
        Invoker     => 'PlainInvoker',
        InvokerType => 'Ticket::TicketUpdate',
        ArticleID   => $HTMLArticleID,
        Expected    => {
            Body        => $HTMLArticle{Body},
            Charset     => 'utf8',
            ContentType => 'text/plain; charset=utf8',
            MimeType    => 'text/plain',
            Subject     => 'HTML article',
        },
    },
);

for my $Test (@Tests) {
    subtest $Test->{Name} => sub {

        my $InvokerObject = Kernel::GenericInterface::Invoker->new(
            DebuggerObject => $DebuggerObject,
            InvokerType    => $Test->{InvokerType},
            Invoker        => $Test->{Invoker},
            WebserviceID   => $WebserviceID,
        );

        isa_ok( $InvokerObject, ['Kernel::GenericInterface::Invoker'], 'invoker object created' );

        my $Result = $InvokerObject->PrepareRequest(
            Data => {
                TicketID  => $TicketID,
                ArticleID => $Test->{ArticleID},
            },
        );

        ok( $Result->{Success}, 'PrepareRequest() successful' . ( $Result->{ErrorMessage} ? " ($Result->{ErrorMessage})" : '' ) );

        # The article is returned twice, in the old and in the new structure. Both must be converted.
        is( $Result->{Data}->{Article}->[0],           $Test->{Expected}, 'article in old structure' );
        is( $Result->{Data}->{Ticket}->{Article}->[0], $Test->{Expected}, 'article in new structure' );
    };
}

done_testing;
