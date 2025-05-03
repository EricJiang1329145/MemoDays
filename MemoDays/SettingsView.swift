//
//  SettingsView.swift
//  MemoDays
//
//  Created by Eric Jiang on 2025/5/3.
//
import SwiftUI
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                generalSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var appearanceSection: some View {
        Section("外观设置") {
            NavigationLink("主题颜色") {
                ColorSettingsView()
            }
            NavigationLink("图标样式") {
                Text("图标样式设置（开发中）")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var generalSection: some View {
        Section("通用设置") {
            NavigationLink("通知设置") {
                Text("通知设置（开发中）")
                    .foregroundStyle(.secondary)
            }
            NavigationLink("数据管理") {
                Text("数据管理（开发中）")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var aboutSection: some View {
        Section("关于") {
            // 在 SettingsView 的 aboutSection 中修改
            HStack {
                Text("版本")
                Spacer()
                Text(Bundle.main.appVersion)
                    .foregroundStyle(.secondary)
            }
            NavigationLink("用户协议") {
                UserAgreementView() // 替换原来的占位视图
            }
        }
    }
}
// 在 Bundle 扩展中添加
extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}
struct UserAgreementView: View {
    var body: some View {
        ScrollView {
            Text("""
            【用户协议】
            
            欢迎使用 MemoDays...
            （这里粘贴完整协议内容）
            """)
            .padding()
        }
        .navigationTitle("用户协议")
        .navigationBarTitleDisplayMode(.inline)
    }
}
// 颜色设置预览视图（后续实现颜色自定义的占位）
struct ColorSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("主题颜色设置")
                .font(.title)
            Text("颜色自定义功能正在开发中...")
                .foregroundStyle(.secondary)
            ProgressView()
        }
        .padding()
        .navigationTitle("主题颜色")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 预览提供程序
#Preview {
    SettingsView()
}
