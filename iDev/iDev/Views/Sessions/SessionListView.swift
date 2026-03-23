import SwiftUI

struct SessionListView: View {
    var body: some View {
        ContentUnavailableView(
            "No Active Sessions",
            systemImage: "terminal",
            description: Text("Connect to a host or resume a workspace to start a session.")
        )
        .navigationTitle("Sessions")
    }
}
