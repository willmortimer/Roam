import Testing
import Foundation
@testable import Roam

@Suite("SSHConfigParser")
struct SSHConfigParserTests {

    @Test("Parse basic host entry")
    func basicHost() {
        let config = """
        Host myserver
            HostName 192.168.1.100
            User admin
            Port 2222
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 1)
        #expect(entries[0].alias == "myserver")
        #expect(entries[0].hostname == "192.168.1.100")
        #expect(entries[0].user == "admin")
        #expect(entries[0].port == 2222)
    }

    @Test("Parse multiple hosts")
    func multipleHosts() {
        let config = """
        Host dev
            HostName dev.example.com
            User deploy

        Host staging
            HostName staging.example.com
            User deploy
            Port 2200
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 2)
        #expect(entries[0].alias == "dev")
        #expect(entries[1].alias == "staging")
        #expect(entries[1].port == 2200)
    }

    @Test("Default port is 22")
    func defaultPort() {
        let config = """
        Host myhost
            HostName example.com
            User root
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries[0].port == 22)
    }

    @Test("Identity file parsed")
    func identityFile() {
        let config = """
        Host myhost
            HostName example.com
            User root
            IdentityFile ~/.ssh/id_ed25519
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries[0].identityFile == "~/.ssh/id_ed25519")
    }

    @Test("ProxyJump parsed")
    func proxyJump() {
        let config = """
        Host internal
            HostName 10.0.0.5
            User admin
            ProxyJump bastion
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries[0].proxyJump == "bastion")
    }

    @Test("Skip wildcard hosts")
    func skipWildcard() {
        let config = """
        Host *
            ServerAliveInterval 60

        Host myhost
            HostName example.com
            User root
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 1)
        #expect(entries[0].alias == "myhost")
    }

    @Test("Skip hosts with patterns")
    func skipPatterns() {
        let config = """
        Host *.example.com
            User deploy

        Host prod
            HostName prod.example.com
            User admin
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 1)
        #expect(entries[0].alias == "prod")
    }

    @Test("Handle comments and blank lines")
    func commentsAndBlanks() {
        let config = """
        # This is a comment
        Host myhost
            # Comment inside host block
            HostName example.com

            User root
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 1)
        #expect(entries[0].hostname == "example.com")
        #expect(entries[0].user == "root")
    }

    @Test("Case insensitive keywords")
    func caseInsensitive() {
        let config = """
        host myhost
            hostname example.com
            user admin
            port 3022
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 1)
        #expect(entries[0].hostname == "example.com")
        #expect(entries[0].user == "admin")
        #expect(entries[0].port == 3022)
    }

    @Test("Tab and space indentation both work")
    func mixedIndentation() {
        let config = "Host myhost\n\tHostName example.com\n    User admin\n"
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 1)
        #expect(entries[0].hostname == "example.com")
    }

    @Test("Equals sign syntax")
    func equalsSignSyntax() {
        let config = """
        Host myhost
            HostName=example.com
            User=admin
            Port=2222
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 1)
        #expect(entries[0].hostname == "example.com")
        #expect(entries[0].user == "admin")
        #expect(entries[0].port == 2222)
    }

    @Test("Empty config produces no entries")
    func emptyConfig() {
        let entries = SSHConfigParser.parse("")
        #expect(entries.isEmpty)
    }

    @Test("Host without HostName uses alias as hostname")
    func aliasAsHostname() {
        let config = """
        Host example.com
            User deploy
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries.count == 1)
        #expect(entries[0].hostname == "example.com")
    }

    @Test("Multi-hop ProxyJump")
    func multiHopProxy() {
        let config = """
        Host deep
            HostName 10.0.0.99
            User admin
            ProxyJump bastion1,bastion2
        """
        let entries = SSHConfigParser.parse(config)
        #expect(entries[0].proxyJump == "bastion1,bastion2")
    }
}
