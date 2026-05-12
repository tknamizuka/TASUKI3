//
//  EkidenSubstituteSheet.swift
//  TASUKI
//
//  代走設定: オーナーが区間担当者を変更
//

import SwiftUI
import FirebaseAuth

struct EkidenSubstituteSheet: View {
    let leg: EkidenLeg
    let state: EkidenViewState
    let teamId: String
    let entryId: String
    let isSampleTeam: Bool
    let onDismiss: () -> Void
    let onSuccess: () -> Void

    @State private var selectedUid: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var candidateUids: [String] {
        Array(state.memberNames.keys).sorted()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("\(leg.id + 1)区の担当者を変更（代走）")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                    Text("新しい担当者を選んでください")
                        .font(.system(size: 13))
                        .foregroundColor(Color.tasukiMutedText)

                    List {
                        ForEach(candidateUids, id: \.self) { uid in
                            Button {
                                selectedUid = uid
                            } label: {
                                HStack {
                                    Text(state.memberNames[uid] ?? uid)
                                        .font(.system(size: 15))
                                        .foregroundColor(Color.tasukiPrimary)
                                    Spacer()
                                    if selectedUid == uid {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color.tasukiAccentOrange)
                                    }
                                }
                            }
                            .listRowBackground(Color.tasukiDarkCard)
                        }
                    }
                    .scrollContentBackground(.hidden)

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button(action: { Task { await saveSubstitute() } }) {
                        if isSaving {
                            ProgressView()
                                .tint(Color.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            Text("代走を確定")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.tasukiOnBrandYellow)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    .disabled(isSaving || selectedUid == leg.assignedUid)
                }
                .padding(20)
            }
            .navigationTitle("代走設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onDismiss() }
                        .foregroundColor(Color.tasukiMutedText)
                }
            }
        }
        .onAppear {
            selectedUid = leg.assignedUid
        }
    }

    private func saveSubstitute() async {
        guard let uid = selectedUid else { return }
        isSaving = true
        errorMessage = nil
        let result = await EkidenDataService.shared.updateLegAssignment(
            teamId: teamId,
            entryId: entryId,
            legIndex: leg.id,
            newAssignedUid: uid,
            isSampleTeam: isSampleTeam
        )
        await MainActor.run {
            isSaving = false
            switch result {
            case .success:
                onSuccess()
                onDismiss()
            case .failure(let e):
                errorMessage = e.localizedDescription
            }
        }
    }
}
