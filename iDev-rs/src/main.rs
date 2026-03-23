pub mod artifacts;
pub mod git;
pub mod process;
pub mod proxy;
pub mod rpc;
pub mod testing;
pub mod tmux;
pub mod tunnel;
pub mod workspace;

use std::sync::Arc;

use clap::{Parser, Subcommand};
use tokio::sync::RwLock;
use tracing_subscriber::EnvFilter;

use rpc::{PingHandler, RpcServer, VersionHandler};

use artifacts::ListRecentHandler;
use git::{
    DiffSummaryHandler, GitBranchListHandler, GitCheckoutHandler, GitCommitHandler,
    GitPullHandler, GitPushHandler, GitStageHandler, GitStashHandler, GitStashListHandler,
    GitStashPopHandler, GitStatusHandler, GitUnstageHandler,
};
use process::{ListPortsHandler, PreviewCandidatesHandler};
use proxy::{ProxyStartHandler, ProxyState, ProxyStatusHandler, ProxyStopHandler};
use testing::ParseReportHandler;
use tmux::{CapturePaneHandler, ListPanesHandler, ListSessionsHandler, SendKeysHandler};
use tunnel::{
    TunnelStartCloudflareHandler, TunnelStartTailscaleHandler, TunnelState, TunnelStatusHandler,
    TunnelStopHandler,
};
use workspace::ResumePlanHandler;

const VERSION: &str = "idev-helper 0.1.0";

#[derive(Parser)]
#[command(name = "idev-helper", version, about = "Helper daemon for iDev iOS remote workspace")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Start the RPC server.
    Serve {
        /// Use stdin/stdout as the transport.
        #[arg(long)]
        stdio: bool,
        /// Listen on a TCP address for RPC connections (e.g., 127.0.0.1:9876).
        #[arg(long)]
        listen: Option<String>,
    },
    /// Print the version string.
    Version,
    /// Quick liveness check -- prints "pong".
    Ping,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Serve { stdio, listen } => {
            // Initialise tracing to stderr so stdout stays clean for RPC.
            tracing_subscriber::fmt()
                .with_writer(std::io::stderr)
                .with_env_filter(EnvFilter::from_default_env())
                .init();

            let mut server = RpcServer::new();

            // Built-in methods
            server.register("ping", PingHandler);
            server.register("version", VersionHandler);

            // C3: tmux introspection
            server.register("tmux.list_sessions", ListSessionsHandler);
            server.register("tmux.list_panes", ListPanesHandler);
            server.register("tmux.capture_pane", CapturePaneHandler);
            server.register("tmux.send_keys", SendKeysHandler);

            // C4: port/process discovery
            server.register("process.list_ports", ListPortsHandler);
            server.register("process.preview_candidates", PreviewCandidatesHandler);

            // C5: git status
            server.register("git.status", GitStatusHandler);
            server.register("git.diff_summary", DiffSummaryHandler);

            // Phase 3: git write operations
            server.register("git.stage", GitStageHandler);
            server.register("git.unstage", GitUnstageHandler);
            server.register("git.commit", GitCommitHandler);
            server.register("git.push", GitPushHandler);
            server.register("git.pull", GitPullHandler);
            server.register("git.branch_list", GitBranchListHandler);
            server.register("git.checkout", GitCheckoutHandler);
            server.register("git.stash", GitStashHandler);
            server.register("git.stash_pop", GitStashPopHandler);
            server.register("git.stash_list", GitStashListHandler);

            // C6: artifact listing
            server.register("artifacts.list_recent", ListRecentHandler);

            // C7: workspace resume plan
            server.register("workspace.resume_plan", ResumePlanHandler);

            // Phase 4: test report parsing
            server.register("testing.parse_report", ParseReportHandler);

            // Phase 4: reverse proxy
            let proxy_state = Arc::new(RwLock::new(ProxyState::default()));
            server.register("proxy.start", ProxyStartHandler { state: Arc::clone(&proxy_state) });
            server.register("proxy.stop", ProxyStopHandler { state: Arc::clone(&proxy_state) });
            server.register("proxy.status", ProxyStatusHandler { state: proxy_state });

            // Phase 4: tunnel management
            let tunnel_state = Arc::new(RwLock::new(TunnelState::default()));
            server.register("tunnel.start_cloudflare", TunnelStartCloudflareHandler { state: Arc::clone(&tunnel_state) });
            server.register("tunnel.start_tailscale", TunnelStartTailscaleHandler { state: Arc::clone(&tunnel_state) });
            server.register("tunnel.stop", TunnelStopHandler { state: Arc::clone(&tunnel_state) });
            server.register("tunnel.status", TunnelStatusHandler { state: tunnel_state });

            if let Some(addr) = listen {
                tracing::info!("{VERSION} starting — TCP transport on {addr}");
                let server = Arc::new(server);
                server.serve_tcp(&addr).await?;
            } else if stdio {
                tracing::info!("{VERSION} starting — stdio transport");
                eprintln!("{VERSION} ready (stdin/stdout RPC)");
                server.serve_stdio().await?;
            } else {
                anyhow::bail!("specify --stdio or --listen <addr>");
            }
        }
        Command::Version => {
            println!("{VERSION}");
        }
        Command::Ping => {
            println!("pong");
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cli_parses_ping() {
        let cli = Cli::parse_from(["idev-helper", "ping"]);
        assert!(matches!(cli.command, Command::Ping));
    }

    #[test]
    fn cli_parses_version() {
        let cli = Cli::parse_from(["idev-helper", "version"]);
        assert!(matches!(cli.command, Command::Version));
    }

    #[test]
    fn cli_parses_serve_stdio() {
        let cli = Cli::parse_from(["idev-helper", "serve", "--stdio"]);
        assert!(matches!(
            cli.command,
            Command::Serve {
                stdio: true,
                listen: None
            }
        ));
    }

    #[test]
    fn cli_parses_serve_listen() {
        let cli = Cli::parse_from(["idev-helper", "serve", "--listen", "127.0.0.1:9876"]);
        match cli.command {
            Command::Serve { stdio, listen } => {
                assert!(!stdio);
                assert_eq!(listen.as_deref(), Some("127.0.0.1:9876"));
            }
            _ => panic!("expected Serve command"),
        }
    }
}
