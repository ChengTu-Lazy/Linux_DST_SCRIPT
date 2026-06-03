package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"crypto/sha1"
	"crypto/tls"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const websocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
const maxFramePayload = 8 * 1024 * 1024
const defaultClientPingIntervalMs = 5000
const defaultClientReadTimeoutMs = 15000
const defaultClientForceReconnectMs = 30000

var wsWriteMu sync.Mutex

var chatBridge = struct {
	sync.Mutex
	Enabled bool
	Cluster string
	Stop    chan struct{}
}{}

const clientWriteTimeout = 10 * time.Second

type Config struct {
	UpstreamURL       string            `json:"upstreamUrl"`
	ScriptPath        string            `json:"scriptPath"`
	Cwd               string            `json:"cwd"`
	Shell             string            `json:"shell"`
	DefaultCluster    string            `json:"defaultCluster"`
	CommandTimeoutMs  int               `json:"commandTimeoutMs"`
	ClientReconnectMs int               `json:"clientReconnectMs"`
	ClientPingMs      int               `json:"clientPingMs"`
	ClientReadTimeout int               `json:"clientReadTimeoutMs"`
	ClientRefreshMs   int               `json:"clientRefreshMs"`
	ClientOutputLimit int               `json:"clientOutputLimit"`
	Token             string            `json:"token"`
	Aliases           map[string]string `json:"aliases"`
	ClusterAliases    map[string]string `json:"clusterAliases"`
}

type ConfigFile struct {
	UpstreamURL       string            `json:"upstreamUrl"`
	ScriptPath        string            `json:"scriptPath"`
	DefaultCluster    string            `json:"defaultCluster"`
	ClientReconnectMs int               `json:"clientReconnectMs"`
	ClientPingMs      int               `json:"clientPingMs"`
	ClientReadTimeout int               `json:"clientReadTimeoutMs"`
	ClientRefreshMs   int               `json:"clientRefreshMs"`
	Token             string            `json:"token"`
	Cwd               string            `json:"cwd,omitempty"`
	Shell             string            `json:"shell,omitempty"`
	CommandTimeoutMs  int               `json:"commandTimeoutMs,omitempty"`
	ClientOutputLimit int               `json:"clientOutputLimit,omitempty"`
	Aliases           map[string]string `json:"aliases,omitempty"`
	ClusterAliases    map[string]string `json:"clusterAliases,omitempty"`
}

type ClientMessage struct {
	Action  string                 `json:"action"`
	Command string                 `json:"command"`
	Cluster string                 `json:"cluster"`
	Args    map[string]interface{} `json:"args"`
}

type ChatBridgeControlMessage struct {
	Type    string `json:"type"`
	Enabled bool   `json:"enabled"`
	Cluster string `json:"cluster,omitempty"`
}

type ChatBridgeSendMessage struct {
	Type    string `json:"type"`
	Cluster string `json:"cluster,omitempty"`
	Text    string `json:"text"`
}

type ChatBridgeEventMessage struct {
	Type    string `json:"type"`
	Cluster string `json:"cluster"`
	World   string `json:"world"`
	User    string `json:"user"`
	Text    string `json:"text"`
}

type CapabilityMessage struct {
	Type           string                      `json:"type"`
	Version        int                         `json:"version"`
	DefaultCluster string                      `json:"defaultCluster,omitempty"`
	Clusters       []ClusterInfo               `json:"clusters,omitempty"`
	Actions        map[string]ActionCapability `json:"actions"`
	Aliases        map[string]string           `json:"aliases"`
	ClusterAliases map[string]string           `json:"clusterAliases,omitempty"`
}

type ActionCapability struct {
	Description string   `json:"description"`
	Aliases     []string `json:"aliases,omitempty"`
	Usage       string   `json:"usage,omitempty"`
	TextArg     string   `json:"textArg,omitempty"`
}

type Action struct {
	Description string
	Usage       string
	TextArg     string
	BuildArgs   func(NormalizedInput) ([]string, error)
}

type NormalizedInput struct {
	Action  string
	Cluster string
	Args    map[string]interface{}
}

type ClusterInfo struct {
	Name        string
	DisplayName string `json:"displayName,omitempty"`
	Worlds      []string
	Running     bool
}

type WSClient struct {
	Conn net.Conn
	R    *bufio.Reader
	Mu   sync.Mutex
}

var defaultAliases = map[string]string{
	"checkprocess":  "checkprocess",
	"getPlayerList": "getPlayerList",
	"startServer":   "startServer",
	"restartServer": "restartServer",
	"restartAuto":   "restartAuto",
	"closeServer":   "closeServer",
	"rollback":      "rollback",
	"rollback1":     "rollback1",
	"rollback2":     "rollback2",
	"rollback3":     "rollback3",
	"rollback4":     "rollback4",
	"rollback5":     "rollback5",
	"listClusters":  "listClusters",
	"getModInfo":    "getModInfo",
	"getWorldInfo":  "getWorldInfo",
	"getChatLog":    "getChatLog",
	"say":           "say",
	"查进程":           "checkprocess",
	"检查进程":          "checkprocess",
	"玩家列表":          "getPlayerList",
	"查看玩家":          "getPlayerList",
	"开服":            "startServer",
	"启动":            "startServer",
	"启动服务器":         "startServer",
	"重启":            "restartAuto",
	"重启服务器":         "restartAuto",
	"关服":            "closeServer",
	"关闭":            "closeServer",
	"关闭服务器":         "closeServer",
	"回档":            "rollback",
	"回滚":            "rollback",
	"回档1":           "rollback1",
	"回档2":           "rollback2",
	"回档3":           "rollback3",
	"回档4":           "rollback4",
	"回档5":           "rollback5",
	"回滚1":           "rollback1",
	"回滚2":           "rollback2",
	"回滚3":           "rollback3",
	"回滚4":           "rollback4",
	"回滚5":           "rollback5",
	"存档列表":          "listClusters",
	"存档":            "listClusters",
	"服务器列表":         "listClusters",
	"列表":            "listClusters",
	"1":             "startServer",
	"2":             "closeServer",
	"3":             "rollback1",
	"模组信息":          "getModInfo",
	"查看模组":          "getModInfo",
	"mod信息":         "getModInfo",
	"世界信息":          "getWorldInfo",
	"查看世界":          "getWorldInfo",
	"世界配置":          "getWorldInfo",
	"聊天记录":          "getChatLog",
	"玩家对话":          "getChatLog",
	"对话记录":          "getChatLog",
	"说话":            "say",
	"公告":            "say",
	"发消息":           "say",
}

var actions = map[string]Action{
	"listClusters": {
		Description: "列出当前发现的运行中和已保存存档。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"__list_clusters"}, nil
		},
	},
	"checkprocess": {
		Description: "只读检查服务器进程状态，不会自动拉起服务器。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"__status", input.Cluster}, nil
		},
	},
	"getPlayerList": {
		Description: "获取并备份玩家列表。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"-get_playerList", input.Cluster}, nil
		},
	},
	"startServer": {
		Description: "启动服务器；如果地上或地下已运行，则不做操作并提示已开启。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"__start_server", input.Cluster}, nil
		},
	},
	"restartServer": {
		Description: "重启服务器，可传 args.autoFlag 为 -AUTO。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			autoFlag, err := optionalChoice(input.Args["autoFlag"], "args.autoFlag", []string{"", "-AUTO"})
			if err != nil {
				return nil, err
			}
			if autoFlag == "" {
				return []string{"-restart_server", input.Cluster}, nil
			}
			return []string{"-restart_server", input.Cluster, autoFlag}, nil
		},
	},
	"restartAuto": {
		Description: "用 -AUTO 标记重启服务器，适合 Koishi 控房命令。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"-restart_server", input.Cluster, "-AUTO"}, nil
		},
	},
	"closeServer": {
		Description: "关闭服务器。该动作通过 source 原脚本后调用 close_server 实现。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"__source_close_server", input.Cluster}, nil
		},
	},
	"rollback1": rollbackAction(1),
	"rollback2": rollbackAction(2),
	"rollback3": rollbackAction(3),
	"rollback4": rollbackAction(4),
	"rollback5": rollbackAction(5),
	"rollback": {
		Description: "向 DST 控制台发送 c_rollback(n)，需要填写要回档的天数。",
		Usage:       "天数",
		TextArg:     "days",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			days, err := requiredPositiveInt(input.Args["days"], "回档天数")
			if err != nil {
				return nil, err
			}
			return []string{"__console_rollback", input.Cluster, strconv.Itoa(days)}, nil
		},
	},
	"getModInfo": {
		Description: "读取当前存档的 modoverrides.lua，并通过 Steam API 获取模组名称和版本号。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"__mod_info", input.Cluster}, nil
		},
	},
	"getWorldInfo": {
		Description: "通过 DST 控制台读取当前世界状态和实体数量，例如芦苇、蜘蛛巢、触手、海象巢等。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"__runtime_world_info", input.Cluster}, nil
		},
	},
	"getChatLog": {
		Description: "查看当前存档 Master/Caves 最近的玩家聊天记录。",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"__chat_log", input.Cluster}, nil
		},
	},
	"say": {
		Description: "向 DST 控制台发送公告，例：公告 今晚 9 点开局。",
		Usage:       "文本",
		TextArg:     "text",
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			text, err := requiredText(input.Args["text"], "公告内容")
			if err != nil {
				return nil, err
			}
			return []string{"__announce", input.Cluster, text}, nil
		},
	},
}

func rollbackAction(days int) Action {
	return Action{
		Description: fmt.Sprintf("向 DST 控制台发送 c_rollback(%d)。", days),
		BuildArgs: func(input NormalizedInput) ([]string, error) {
			return []string{"__console_rollback", input.Cluster, strconv.Itoa(days)}, nil
		},
	}
}

var config Config
var clientCommandMu sync.Mutex
var ansiPattern = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]`)

type ConfigCreatedError struct {
	Path string
}

func (err *ConfigCreatedError) Error() string {
	return fmt.Sprintf("未找到配置文件，已创建默认配置：%s\n请运行 `%s` 按提示填写 Koishi WebSocket 地址和 token，或直接编辑该文件后重新启动。", err.Path, configCommandForPath(err.Path))
}

func main() {
	if handled, err := handleCLI(os.Args[1:]); handled {
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	loaded, err := loadConfig()
	if err != nil {
		var createdErr *ConfigCreatedError
		if errors.As(err, &createdErr) {
			fmt.Fprintln(os.Stderr, createdErr.Error())
			os.Exit(1)
		}
		log.Fatal(err)
	}
	config = loaded
	runClientMode()
}

func loadConfig() (Config, error) {
	configPath := findConfigPath()
	raw := Config{}
	if fileExists(configPath) {
		content, err := os.ReadFile(configPath)
		if err != nil {
			return Config{}, err
		}
		if err := json.Unmarshal(content, &raw); err != nil {
			return Config{}, err
		}
	} else {
		if err := createDefaultConfigFile(configPath); err != nil {
			return Config{}, err
		}
		if os.Getenv("DST_WS_UPSTREAM") != "" && os.Getenv("DST_WS_TOKEN") != "" {
			raw = Config{}
		} else {
			return Config{}, &ConfigCreatedError{Path: configPath}
		}
	}

	if raw.UpstreamURL == "" {
		raw.UpstreamURL = os.Getenv("DST_WS_UPSTREAM")
	}
	if raw.ScriptPath == "" {
		raw.ScriptPath = getenvDefault("DST_SCRIPT_PATH", "./DST_SCRIPT.sh")
	}
	if raw.Shell == "" {
		raw.Shell = getenvDefault("DST_SCRIPT_SHELL", "bash")
	}
	if raw.DefaultCluster == "" {
		raw.DefaultCluster = os.Getenv("DST_DEFAULT_CLUSTER")
	}
	if value := os.Getenv("DST_COMMAND_TIMEOUT_MS"); value != "" {
		timeout, err := strconv.Atoi(value)
		if err != nil {
			return Config{}, fmt.Errorf("DST_COMMAND_TIMEOUT_MS 无效: %w", err)
		}
		raw.CommandTimeoutMs = timeout
	}
	if raw.CommandTimeoutMs == 0 {
		raw.CommandTimeoutMs = 600000
	}
	if value := os.Getenv("DST_WS_CLIENT_RECONNECT_MS"); value != "" {
		reconnectMs, err := strconv.Atoi(value)
		if err != nil {
			return Config{}, fmt.Errorf("DST_WS_CLIENT_RECONNECT_MS 无效: %w", err)
		}
		raw.ClientReconnectMs = reconnectMs
	}
	if raw.ClientReconnectMs == 0 {
		raw.ClientReconnectMs = 1000
	}
	if value := os.Getenv("DST_WS_CLIENT_PING_MS"); value != "" {
		pingMs, err := strconv.Atoi(value)
		if err != nil {
			return Config{}, fmt.Errorf("DST_WS_CLIENT_PING_MS 无效: %w", err)
		}
		raw.ClientPingMs = pingMs
	}
	if raw.ClientPingMs == 0 {
		raw.ClientPingMs = defaultClientPingIntervalMs
	}
	if value := os.Getenv("DST_WS_CLIENT_READ_TIMEOUT_MS"); value != "" {
		readTimeoutMs, err := strconv.Atoi(value)
		if err != nil {
			return Config{}, fmt.Errorf("DST_WS_CLIENT_READ_TIMEOUT_MS 无效: %w", err)
		}
		raw.ClientReadTimeout = readTimeoutMs
	}
	if raw.ClientReadTimeout == 0 {
		raw.ClientReadTimeout = defaultClientReadTimeoutMs
	}
	if value := os.Getenv("DST_WS_CLIENT_REFRESH_MS"); value != "" {
		refreshMs, err := strconv.Atoi(value)
		if err != nil {
			return Config{}, fmt.Errorf("DST_WS_CLIENT_REFRESH_MS 无效: %w", err)
		}
		raw.ClientRefreshMs = refreshMs
	}
	if raw.ClientRefreshMs == 0 {
		raw.ClientRefreshMs = defaultClientForceReconnectMs
	}
	if value := os.Getenv("DST_WS_CLIENT_OUTPUT_LIMIT"); value != "" {
		outputLimit, err := strconv.Atoi(value)
		if err != nil {
			return Config{}, fmt.Errorf("DST_WS_CLIENT_OUTPUT_LIMIT 无效: %w", err)
		}
		raw.ClientOutputLimit = outputLimit
	}
	if raw.ClientOutputLimit == 0 {
		raw.ClientOutputLimit = 3500
	}

	scriptPath, err := resolvePath(raw.ScriptPath)
	if err != nil {
		return Config{}, err
	}
	raw.ScriptPath = scriptPath
	if !fileExists(raw.ScriptPath) {
		return Config{}, fmt.Errorf("脚本不存在: %s", raw.ScriptPath)
	}

	if raw.Cwd == "" {
		raw.Cwd = filepath.Dir(raw.ScriptPath)
	} else {
		cwd, err := resolvePath(raw.Cwd)
		if err != nil {
			return Config{}, err
		}
		raw.Cwd = cwd
	}

	if token := os.Getenv("DST_WS_TOKEN"); token != "" {
		raw.Token = token
	}
	raw.Token = strings.TrimSpace(raw.Token)
	if raw.Token == "" {
		return Config{}, errors.New("未配置 websocket token。请在 ~/.dst-ws-client/config.json 的 token 中配置，或设置 DST_WS_TOKEN")
	}

	aliases := map[string]string{}
	for key, value := range defaultAliases {
		aliases[key] = value
	}
	for key, value := range raw.Aliases {
		aliases[key] = value
	}
	raw.Aliases = aliases
	if raw.ClusterAliases == nil {
		raw.ClusterAliases = map[string]string{}
	}
	if value := os.Getenv("DST_CLUSTER_ALIASES"); value != "" {
		aliases, err := parseClusterAliases(value)
		if err != nil {
			return Config{}, err
		}
		for alias, cluster := range aliases {
			raw.ClusterAliases[alias] = cluster
		}
	}

	if raw.CommandTimeoutMs <= 0 {
		return Config{}, fmt.Errorf("commandTimeoutMs 必须是正整数")
	}
	if raw.ClientReconnectMs <= 0 {
		return Config{}, fmt.Errorf("clientReconnectMs 必须是正整数")
	}
	if raw.ClientPingMs <= 0 {
		return Config{}, fmt.Errorf("clientPingMs 必须是正整数")
	}
	if raw.ClientReadTimeout <= 0 {
		return Config{}, fmt.Errorf("clientReadTimeoutMs 必须是正整数")
	}
	if raw.ClientReadTimeout <= raw.ClientPingMs {
		return Config{}, fmt.Errorf("clientReadTimeoutMs 必须大于 clientPingMs")
	}
	if raw.ClientRefreshMs <= 0 {
		return Config{}, fmt.Errorf("clientRefreshMs 必须是正整数")
	}
	if raw.ClientOutputLimit <= 0 {
		return Config{}, fmt.Errorf("clientOutputLimit 必须是正整数")
	}
	if strings.TrimSpace(raw.UpstreamURL) == "" {
		return Config{}, errors.New("必须配置 upstreamUrl 或 DST_WS_UPSTREAM")
	}

	return raw, nil
}

func handleCLI(args []string) (bool, error) {
	command, rest := commandArgs(args)
	switch command {
	case "":
		return false, nil
	case "-h", "--help", "help":
		printUsage()
		return true, nil
	case "config":
		return true, runConfigCommand(rest)
	default:
		return false, nil
	}
}

func commandArgs(args []string) (string, []string) {
	cleaned := []string{}
	for index := 0; index < len(args); index++ {
		arg := args[index]
		if arg == "--config" {
			index++
			continue
		}
		if strings.HasPrefix(arg, "--config=") {
			continue
		}
		cleaned = append(cleaned, arg)
	}
	if len(cleaned) == 0 {
		return "", nil
	}
	return cleaned[0], cleaned[1:]
}

func runConfigCommand(args []string) error {
	subcommand, _ := commandArgs(args)
	switch subcommand {
	case "", "wizard", "edit":
		return runConfigWizard()
	case "init":
		path := findConfigPath()
		if fileExists(path) {
			fmt.Printf("配置文件已存在：%s\n", path)
			return nil
		}
		if err := createDefaultConfigFile(path); err != nil {
			return err
		}
		fmt.Printf("已创建默认配置：%s\n", path)
		fmt.Printf("继续运行 `%s` 按提示填写配置。\n", configCommandForPath(path))
		return nil
	case "path":
		fmt.Println(findConfigPath())
		return nil
	case "show":
		raw, err := readConfigFile(findConfigPath())
		if err != nil {
			return err
		}
		raw = applyConfigFileDefaults(raw)
		if raw.Token != "" {
			raw.Token = "REDACTED"
		}
		content, err := json.MarshalIndent(configFileFromConfig(raw), "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(content))
		return nil
	case "-h", "--help", "help":
		printConfigUsage()
		return nil
	default:
		return fmt.Errorf("未知 config 命令：%s", subcommand)
	}
}

func runConfigWizard() error {
	configPath := findConfigPath()
	raw := Config{}
	created := false
	if fileExists(configPath) {
		loaded, err := readConfigFile(configPath)
		if err != nil {
			return err
		}
		raw = loaded
	} else {
		raw = defaultConfigFile()
		created = true
	}
	raw = applyConfigFileDefaults(raw)

	reader := bufio.NewReader(os.Stdin)
	fmt.Printf("配置文件：%s\n", configPath)
	if created {
		fmt.Println("当前还没有配置文件，向导会在最后自动创建。")
	}
	fmt.Println("直接回车会保留方括号里的当前值。")

	var err error
	raw.UpstreamURL, err = promptConfigString(reader, "Koishi WebSocket 地址", raw.UpstreamURL)
	if err != nil {
		return err
	}
	raw.Token, err = promptConfigToken(reader, raw.Token)
	if err != nil {
		return err
	}
	raw.ScriptPath, err = promptConfigString(reader, "DST_SCRIPT.sh 路径", raw.ScriptPath)
	if err != nil {
		return err
	}
	raw.DefaultCluster, err = promptConfigString(reader, "默认存档名(auto 表示自动发现)", raw.DefaultCluster)
	if err != nil {
		return err
	}
	raw.ClientReconnectMs, err = promptConfigInt(reader, "断线重连间隔毫秒", raw.ClientReconnectMs)
	if err != nil {
		return err
	}
	raw.ClientPingMs, err = promptConfigInt(reader, "WebSocket ping 间隔毫秒", raw.ClientPingMs)
	if err != nil {
		return err
	}
	for {
		raw.ClientReadTimeout, err = promptConfigInt(reader, "读超时毫秒", raw.ClientReadTimeout)
		if err != nil {
			return err
		}
		if raw.ClientReadTimeout > raw.ClientPingMs {
			break
		}
		fmt.Printf("读超时必须大于 ping 间隔，目前 ping 间隔是 %d 毫秒。\n", raw.ClientPingMs)
	}
	raw.ClientRefreshMs, err = promptConfigInt(reader, "空闲主动刷新连接间隔毫秒", raw.ClientRefreshMs)
	if err != nil {
		return err
	}

	if err := writeConfigFile(configPath, raw); err != nil {
		return err
	}
	fmt.Printf("配置已保存：%s\n", configPath)
	if strings.TrimSpace(raw.Token) == "" {
		fmt.Println("提示：token 仍为空，启动前需要填入 Koishi WSSUserList 中对应的 Token。")
		return nil
	}
	fmt.Printf("现在可以运行 `%s` 启动客户端。\n", startCommandForPath(configPath))
	return nil
}

func promptConfigString(reader *bufio.Reader, label string, current string) (string, error) {
	fmt.Printf("%s [%s]: ", label, current)
	value, err := readPromptLine(reader)
	if err != nil {
		return "", err
	}
	if value == "" {
		return current, nil
	}
	return value, nil
}

func promptConfigToken(reader *bufio.Reader, current string) (string, error) {
	if current == "" {
		fmt.Print("Koishi Token []: ")
	} else {
		fmt.Print("Koishi Token [已设置，回车保持]: ")
	}
	value, err := readPromptLine(reader)
	if err != nil {
		return "", err
	}
	if value == "" {
		return current, nil
	}
	return value, nil
}

func promptConfigInt(reader *bufio.Reader, label string, current int) (int, error) {
	for {
		fmt.Printf("%s [%d]: ", label, current)
		value, err := readPromptLine(reader)
		if err != nil {
			return 0, err
		}
		if value == "" {
			return current, nil
		}
		number, err := strconv.Atoi(value)
		if err != nil || number <= 0 {
			fmt.Println("请输入正整数。")
			continue
		}
		return number, nil
	}
}

func readPromptLine(reader *bufio.Reader) (string, error) {
	value, err := reader.ReadString('\n')
	if err != nil && !(errors.Is(err, io.EOF) && value != "") {
		return "", err
	}
	value = strings.TrimPrefix(value, "\ufeff")
	return strings.TrimSpace(value), nil
}

func createDefaultConfigFile(path string) error {
	return writeConfigFile(path, defaultConfigFile())
}

func readConfigFile(path string) (Config, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	raw := Config{}
	if err := json.Unmarshal(content, &raw); err != nil {
		return Config{}, err
	}
	return raw, nil
}

func writeConfigFile(path string, raw Config) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	raw = applyConfigFileDefaults(raw)
	content, err := json.MarshalIndent(configFileFromConfig(raw), "", "  ")
	if err != nil {
		return err
	}
	content = append(content, '\n')
	return os.WriteFile(path, content, 0600)
}

func defaultConfigFile() Config {
	return Config{
		UpstreamURL:       "ws://127.0.0.1:12000",
		ScriptPath:        "./DST_SCRIPT.sh",
		DefaultCluster:    "auto",
		ClientReconnectMs: 1000,
		ClientPingMs:      defaultClientPingIntervalMs,
		ClientReadTimeout: defaultClientReadTimeoutMs,
		ClientRefreshMs:   defaultClientForceReconnectMs,
		Token:             "",
	}
}

func applyConfigFileDefaults(raw Config) Config {
	defaults := defaultConfigFile()
	if raw.UpstreamURL == "" {
		raw.UpstreamURL = defaults.UpstreamURL
	}
	if raw.ScriptPath == "" {
		raw.ScriptPath = defaults.ScriptPath
	}
	if raw.DefaultCluster == "" {
		raw.DefaultCluster = defaults.DefaultCluster
	}
	if raw.ClientReconnectMs == 0 {
		raw.ClientReconnectMs = defaults.ClientReconnectMs
	}
	if raw.ClientPingMs == 0 {
		raw.ClientPingMs = defaults.ClientPingMs
	}
	if raw.ClientReadTimeout == 0 {
		raw.ClientReadTimeout = defaults.ClientReadTimeout
	}
	if raw.ClientRefreshMs == 0 {
		raw.ClientRefreshMs = defaults.ClientRefreshMs
	}
	return raw
}

func configFileFromConfig(raw Config) ConfigFile {
	return ConfigFile{
		UpstreamURL:       raw.UpstreamURL,
		ScriptPath:        raw.ScriptPath,
		DefaultCluster:    raw.DefaultCluster,
		ClientReconnectMs: raw.ClientReconnectMs,
		ClientPingMs:      raw.ClientPingMs,
		ClientReadTimeout: raw.ClientReadTimeout,
		ClientRefreshMs:   raw.ClientRefreshMs,
		Token:             raw.Token,
		Cwd:               raw.Cwd,
		Shell:             raw.Shell,
		CommandTimeoutMs:  raw.CommandTimeoutMs,
		ClientOutputLimit: raw.ClientOutputLimit,
		Aliases:           raw.Aliases,
		ClusterAliases:    raw.ClusterAliases,
	}
}

func printUsage() {
	name := programCommand()
	fmt.Printf("用法：\n  %s                 启动客户端\n  %s config          交互式修改配置\n  %s config init     创建默认配置\n  %s config path     输出配置文件路径\n  %s config show     查看配置(token 会隐藏)\n\n可用 --config <path> 指定配置文件。\n", name, name, name, name, name)
}

func printConfigUsage() {
	name := programCommand()
	fmt.Printf("用法：\n  %s config          交互式修改配置\n  %s config init     创建默认配置\n  %s config path     输出配置文件路径\n  %s config show     查看配置(token 会隐藏)\n\n示例：\n  %s --config ./config.json config\n", name, name, name, name, name)
}

func programCommand() string {
	raw := strings.TrimSpace(os.Args[0])
	name := filepath.Base(raw)
	if name == "." || name == string(filepath.Separator) || name == "" {
		name = "dst-ws-client"
	}
	if strings.ContainsAny(raw, `/\`) {
		return quoteCommandPath(raw)
	}
	return "./" + name
}

func configCommandForPath(path string) string {
	return commandForPath(path, " config")
}

func startCommandForPath(path string) string {
	return commandForPath(path, "")
}

func commandForPath(path string, suffix string) string {
	name := programCommand()
	if samePath(path, defaultConfigPath()) {
		return name + suffix
	}
	return name + " --config " + quoteCommandPath(path) + suffix
}

func samePath(left string, right string) bool {
	leftAbs, leftErr := resolvePath(left)
	rightAbs, rightErr := resolvePath(right)
	if leftErr == nil && rightErr == nil {
		return leftAbs == rightAbs
	}
	return filepath.Clean(left) == filepath.Clean(right)
}

func quoteCommandPath(path string) string {
	if !strings.ContainsAny(path, " \t\"") {
		return path
	}
	return `"` + strings.ReplaceAll(path, `"`, `\"`) + `"`
}

func runClientMode() {
	upstream := upstreamURLWithToken(config.UpstreamURL)
	log.Printf("[client] connecting to %s", redactedURL(upstream))
	log.Printf("[script] %s %s", config.Shell, config.ScriptPath)
	announced := false
	for {
		client, err := dialWebSocket(upstream)
		if err != nil {
			log.Printf("[client] connect failed: %v", err)
			time.Sleep(time.Duration(config.ClientReconnectMs) * time.Millisecond)
			continue
		}
		log.Printf("[client] connected")
		stopHeartbeat := startClientHeartbeat(client)
		if !announced {
			writeClientText(client, connectedMessage())
			announced = true
		}
		writeClientText(client, capabilityMessage())
		readClientLoop(client)
		stopHeartbeat()
		_ = client.Conn.Close()
		log.Printf("[client] disconnected, reconnecting in %dms", config.ClientReconnectMs)
		time.Sleep(time.Duration(config.ClientReconnectMs) * time.Millisecond)
	}
}

func readClientLoop(client *WSClient) {
	for {
		_ = client.Conn.SetReadDeadline(time.Now().Add(time.Duration(config.ClientReadTimeout) * time.Millisecond))
		opcode, payload, err := readFrameFrom(client.R, false)
		if err != nil {
			log.Printf("[client] read failed: %v", err)
			return
		}
		switch opcode {
		case 0x1:
			text := strings.TrimSpace(string(payload))
			if shouldIgnoreKoishiMessage(text) {
				continue
			}
			if handleKoishiControlMessage(client, text) {
				continue
			}
			go handleKoishiCommand(client, text)
		case 0x8:
			log.Printf("[client] server closed websocket: %s", describeClosePayload(payload))
			wsWriteMu.Lock()
			_ = writeClientFrame(client, 0x8, payload)
			wsWriteMu.Unlock()
			return
		case 0x9:
			wsWriteMu.Lock()
			_ = writeClientFrame(client, 0xA, payload)
			wsWriteMu.Unlock()
		case 0xA:
			continue
		}
	}
}

func startClientHeartbeat(client *WSClient) func() {
	done := make(chan struct{})
	var once sync.Once
	go func() {
		ticker := time.NewTicker(time.Duration(config.ClientPingMs) * time.Millisecond)
		refreshTicker := time.NewTicker(time.Duration(config.ClientRefreshMs) * time.Millisecond)
		defer ticker.Stop()
		defer refreshTicker.Stop()
		for {
			select {
			case <-done:
				return
			case <-ticker.C:
				wsWriteMu.Lock()
				if err := writeClientFrame(client, 0x9, []byte("ping")); err != nil {
					wsWriteMu.Unlock()
					log.Printf("[client] heartbeat failed: %v", err)
					_ = client.Conn.Close()
					return
				}
				wsWriteMu.Unlock()
			case <-refreshTicker.C:
				chatBridge.Lock()
				bridgeEnabled := chatBridge.Enabled
				chatBridge.Unlock()
				if bridgeEnabled {
					log.Printf("[client] refresh skipped: chat bridge enabled")
					continue
				}
				if clientCommandMu.TryLock() {
					clientCommandMu.Unlock()
					log.Printf("[client] refreshing websocket connection")
					_ = client.Conn.Close()
					return
				}
				log.Printf("[client] refresh skipped: command running")
			}
		}
	}()
	return func() {
		once.Do(func() {
			close(done)
		})
	}
}

func describeClosePayload(payload []byte) string {
	if len(payload) < 2 {
		return "no close code"
	}
	code := binary.BigEndian.Uint16(payload[:2])
	reason := strings.TrimSpace(string(payload[2:]))
	if reason == "" {
		return fmt.Sprintf("code=%d", code)
	}
	return fmt.Sprintf("code=%d reason=%q", code, reason)
}

func shouldIgnoreKoishiMessage(text string) bool {
	return text == "" ||
		strings.HasPrefix(text, "欢迎连接到DST服务器") ||
		strings.HasPrefix(text, "服务端已收到:")
}

func handleKoishiControlMessage(client *WSClient, text string) bool {
	if !strings.HasPrefix(text, "{") {
		return false
	}

	var probe struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal([]byte(text), &probe); err != nil {
		return false
	}
	switch probe.Type {
	case "dst-search.chat-control":
		var message ChatBridgeControlMessage
		if err := json.Unmarshal([]byte(text), &message); err != nil {
			log.Printf("[chat-bridge] invalid control message: %v", err)
			return true
		}
		cluster := strings.TrimSpace(message.Cluster)
		if cluster == "" {
			resolved, err := resolveDefaultCluster()
			if err != nil {
				log.Printf("[chat-bridge] resolve default cluster failed: %v", err)
				return true
			}
			cluster = resolved
		}
		if message.Enabled {
			startChatBridge(client, cluster)
		} else {
			stopChatBridge()
		}
		return true
	case "dst-search.chat-send":
		var message ChatBridgeSendMessage
		if err := json.Unmarshal([]byte(text), &message); err != nil {
			log.Printf("[chat-bridge] invalid send message: %v", err)
			return true
		}
		cluster := strings.TrimSpace(message.Cluster)
		if cluster == "" {
			resolved, err := resolveDefaultCluster()
			if err != nil {
				log.Printf("[chat-bridge] resolve default cluster failed: %v", err)
				return true
			}
			cluster = resolved
		}
		go func() {
			if err := sendDSTAnnouncement(cluster, message.Text); err != nil {
				log.Printf("[chat-bridge] send to DST failed: %v", err)
			}
		}()
		return true
	default:
		return false
	}
}

func handleKoishiCommand(client *WSClient, text string) {
	request := ClientMessage{Command: text}
	action, argv, err := buildCLIArgs(request)
	if err != nil {
		writeClientText(client, err.Error())
		return
	}
	if action == "listClusters" {
		writeClientText(client, formatClusterList())
		return
	}
	if !clientCommandMu.TryLock() {
		writeClientText(client, "已有命令正在执行，请稍后再试。")
		return
	}
	defer clientCommandMu.Unlock()

	log.Printf("[client-run] %s %s", action, strings.Join(argv, " "))

	timeoutMs := commandTimeoutMs(action)
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()

	startedAt := time.Now()
	cmd := newScriptCommand(ctx, argv)
	output, err := cmd.CombinedOutput()
	timedOut := errors.Is(ctx.Err(), context.DeadlineExceeded)
	if timedOut {
		killCommandGroup(cmd)
	}
	code := exitCode(err)
	duration := time.Since(startedAt).Round(time.Second)

	writeClientText(client, formatCommandResult(action, string(output), code, err, timedOut, duration))
}

func formatCommandResult(action string, output string, code int, err error, timedOut bool, duration time.Duration) string {
	body := cleanForChat(output, config.ClientOutputLimit)
	body = simplifyActionOutput(action, body)

	if code == 0 && !timedOut {
		if body != "" {
			return body
		}
		return successMessage(action, duration)
	}

	status := fmt.Sprintf("%s 执行失败，退出码 %d", action, code)
	if timedOut {
		status += "，已超时"
	}
	if err != nil && code == -1 {
		status += "：" + err.Error()
	}
	if body == "" {
		return status
	}
	return status + "\n" + body
}

func successMessage(action string, duration time.Duration) string {
	switch action {
	case "startServer", "restartAuto", "restartServer":
		return fmt.Sprintf("开服/重启命令已结束，用时 %s。", duration)
	case "closeServer":
		return fmt.Sprintf("关服命令已结束，用时 %s。", duration)
	case "say":
		return "公告已发送。"
	default:
		return "执行成功。"
	}
}

func simplifyActionOutput(action string, body string) string {
	body = strings.TrimSpace(body)
	if body == "" {
		return ""
	}
	switch action {
	case "startServer", "restartAuto", "restartServer", "closeServer":
		return summarizeLongServerOutput(action, body)
	case "getPlayerList":
		return summarizePlayerListOutput(body)
	case "say":
		return summarizeSayOutput(body)
	default:
		return body
	}
}

func summarizeLongServerOutput(action string, body string) string {
	lines := filterNoiseLines(strings.Split(body, "\n"))
	if len(lines) == 0 {
		return successMessage(action, 0)
	}
	title := "执行结果"
	if action == "startServer" || action == "restartAuto" || action == "restartServer" {
		title = "开服/重启结果"
	} else if action == "closeServer" {
		title = "关服结果"
	}
	statusLines := filterLinesContaining(lines, "状态确认")
	if len(statusLines) > 0 {
		return title + "\n" + strings.Join(statusLines, "\n")
	}
	keyLines := pickServerResultLines(lines)
	if len(keyLines) > 0 {
		lines = keyLines
	} else {
		lines = tailLines(lines, 8)
	}
	return title + "\n" + strings.Join(lines, "\n")
}

func filterLinesContaining(lines []string, value string) []string {
	result := make([]string, 0, len(lines))
	for _, line := range lines {
		if strings.Contains(line, value) {
			result = append(result, line)
		}
	}
	return result
}

func summarizeSayOutput(body string) string {
	prefix := "sent announce to "
	if strings.HasPrefix(body, prefix) {
		if index := strings.LastIndex(body, ": "); index >= 0 && index+2 < len(body) {
			return "公告已发送：" + strings.TrimSpace(body[index+2:])
		}
		return "公告已发送。"
	}
	return body
}

func summarizePlayerListOutput(body string) string {
	lines := filterNoiseLines(strings.Split(body, "\n"))
	if len(lines) == 0 {
		return "没有读取到玩家列表。"
	}
	return strings.Join(tailLines(lines, 20), "\n")
}

func pickServerResultLines(lines []string) []string {
	keywords := []string{
		"启动成功",
		"启动完成",
		"开启成功",
		"已开启",
		"服务器运行正常",
		"状态确认",
		"运行中",
		"关闭成功",
		"已关闭",
		"关服完成",
		"重启完成",
		"失败",
		"错误",
		"异常",
		"超时",
		"running",
		"started",
		"stopped",
		"failed",
		"error",
	}
	result := make([]string, 0, 8)
	for _, line := range lines {
		lower := strings.ToLower(line)
		for _, keyword := range keywords {
			if strings.Contains(lower, strings.ToLower(keyword)) {
				result = append(result, line)
				break
			}
		}
	}
	if len(result) > 8 {
		return tailLines(result, 8)
	}
	return result
}

func filterNoiseLines(lines []string) []string {
	result := make([]string, 0, len(lines))
	seen := map[string]bool{}
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || isNoiseLine(line) {
			continue
		}
		if seen[line] {
			continue
		}
		seen[line] = true
		result = append(result, line)
	}
	return result
}

func isNoiseLine(line string) bool {
	trimmed := strings.Trim(line, "= #-\t")
	if trimmed == "" {
		return true
	}
	noiseParts := []string{
		"There is a screen on:",
		"No screen session found",
		"Sockets in /run/screen",
		"Socket in /run/screen",
		"screen size is bogus",
		"正在处理.",
		"正在处理..",
		"正在处理...",
		"等待.",
		"等待..",
		"等待...",
		"启动.",
		"启动..",
		"启动...",
	}
	for _, part := range noiseParts {
		if strings.Contains(line, part) {
			return true
		}
	}
	return false
}

func tailLines(lines []string, limit int) []string {
	if limit <= 0 || len(lines) <= limit {
		return lines
	}
	return lines[len(lines)-limit:]
}

func commandTimeoutMs(action string) int {
	switch action {
	case "checkprocess", "getWorldInfo", "getChatLog", "say":
		return 15000
	case "getModInfo":
		return 30000
	case "getPlayerList":
		return 30000
	case "startServer", "restartAuto", "restartServer":
		return 90000
	default:
		return config.CommandTimeoutMs
	}
}

func startChatBridge(client *WSClient, cluster string) {
	cluster = strings.TrimSpace(cluster)
	if cluster == "" {
		return
	}

	chatBridge.Lock()
	if chatBridge.Stop != nil {
		close(chatBridge.Stop)
	}
	stop := make(chan struct{})
	chatBridge.Enabled = true
	chatBridge.Cluster = cluster
	chatBridge.Stop = stop
	chatBridge.Unlock()

	go pollChatLog(client, cluster, stop)
	log.Printf("[chat-bridge] enabled for %s", cluster)
}

func stopChatBridge() {
	chatBridge.Lock()
	if chatBridge.Stop != nil {
		close(chatBridge.Stop)
	}
	chatBridge.Enabled = false
	chatBridge.Cluster = ""
	chatBridge.Stop = nil
	chatBridge.Unlock()
	log.Printf("[chat-bridge] disabled")
}

func pollChatLog(client *WSClient, cluster string, stop <-chan struct{}) {
	world, path, err := resolveChatLogPath(cluster)
	if err != nil {
		log.Printf("[chat-bridge] resolve chat log failed: %v", err)
		return
	}
	displayCluster := resolveClusterDisplayName(cluster)

	var offset int64
	if stat, err := os.Stat(path); err == nil {
		offset = stat.Size()
	}

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			newOffset, err := readNewChatLines(client, displayCluster, world, path, offset)
			if err != nil {
				log.Printf("[chat-bridge] read chat log failed: %v", err)
				continue
			}
			offset = newOffset
		}
	}
}

func resolveChatLogPath(cluster string) (string, string, error) {
	script := fmt.Sprintf(
		"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; base=\"$DST_SAVE_PATH/%s\"; for world in Master Caves Shipwrecked Volcano; do file=\"$base/$world/server_chat_log.txt\"; if [ -f \"$file\" ]; then printf '%%s\\t%%s\\n' \"$world\" \"$file\"; exit 0; fi; done; exit 1",
		shellQuote(config.ScriptPath),
		shellQuote(cluster),
		shellEscapeForDoubleQuoted(cluster),
	)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, config.Shell, "-lc", script).Output()
	if err != nil {
		return "", "", err
	}
	parts := strings.SplitN(strings.TrimSpace(string(output)), "\t", 2)
	if len(parts) != 2 {
		return "", "", fmt.Errorf("invalid chat log path output: %q", strings.TrimSpace(string(output)))
	}
	return displayWorldName(parts[0]), parts[1], nil
}

func resolveClusterDisplayName(cluster string) string {
	if name := readClusterDisplayNameFromFile(cluster); name != "" {
		return name
	}
	script := fmt.Sprintf(
		"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; file=\"$DST_SAVE_PATH/%s/cluster.ini\"; if [ -f \"$file\" ]; then awk -F '=' '/^[[:space:]]*cluster_name[[:space:]]*=/{value=$2; sub(/^[[:space:]]+/, \"\", value); sub(/[[:space:]]+$/, \"\", value); print value; exit}' \"$file\"; fi",
		shellQuote(config.ScriptPath),
		shellQuote(cluster),
		shellEscapeForDoubleQuoted(cluster),
	)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, config.Shell, "-lc", script).Output()
	if err != nil {
		log.Printf("[chat-bridge] resolve cluster display name failed: %v", err)
		return cluster
	}
	name := strings.TrimSpace(string(output))
	if name == "" {
		return cluster
	}
	return name
}

func readClusterDisplayNameFromFile(cluster string) string {
	cluster = strings.TrimSpace(cluster)
	if cluster == "" {
		return ""
	}
	data, err := os.ReadFile(filepath.Join(detectSavePath(), cluster, "cluster.ini"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		key, value, ok := strings.Cut(line, "=")
		if !ok || strings.TrimSpace(key) != "cluster_name" {
			continue
		}
		return strings.TrimSpace(value)
	}
	return ""
}

func clusterDisplayLabel(cluster string) string {
	displayName := resolveClusterDisplayName(cluster)
	if displayName == "" || displayName == cluster {
		return cluster
	}
	return fmt.Sprintf("%s (%s)", displayName, cluster)
}

func clusterInfoLabel(cluster ClusterInfo) string {
	displayName := strings.TrimSpace(cluster.DisplayName)
	if displayName == "" {
		displayName = resolveClusterDisplayName(cluster.Name)
	}
	if displayName == "" || displayName == cluster.Name {
		return cluster.Name
	}
	return fmt.Sprintf("%s (%s)", displayName, cluster.Name)
}

func readNewChatLines(client *WSClient, clusterName string, world string, path string, offset int64) (int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return offset, err
	}
	defer file.Close()

	stat, err := file.Stat()
	if err != nil {
		return offset, err
	}
	if stat.Size() < offset {
		offset = 0
	}
	if _, err := file.Seek(offset, io.SeekStart); err != nil {
		return offset, err
	}

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		user, text, ok := parseDSTChatLine(scanner.Text())
		if !ok {
			continue
		}
		sendChatBridgeEvent(client, ChatBridgeEventMessage{
			Type:    "dst-ws-client.chat",
			Cluster: clusterName,
			World:   world,
			User:    user,
			Text:    text,
		})
	}
	if err := scanner.Err(); err != nil {
		return offset, err
	}
	return stat.Size(), nil
}

func parseDSTChatLine(line string) (string, string, bool) {
	line = strings.TrimSpace(line)
	if line == "" || strings.Contains(line, "[Announcement]") {
		return "", "", false
	}
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`^\[[^\]]+\]:\s*\[(?:Say|Whisper|Yell|Chat)\]\s*(?:\([^)]*\)\s*)?([^:]+):\s*(.+)$`),
		regexp.MustCompile(`^\[[^\]]+\]:\s*(?:\[[^\]]+\]\s*)?(?:\([^)]*\)\s*)?([^:]+):\s*(.+)$`),
	}
	for _, pattern := range patterns {
		matches := pattern.FindStringSubmatch(line)
		if len(matches) != 3 {
			continue
		}
		user := strings.TrimSpace(matches[1])
		text := strings.TrimSpace(matches[2])
		if user == "" || text == "" || strings.HasPrefix(user, "[") {
			return "", "", false
		}
		return user, text, true
	}
	return "", "", false
}

func sendChatBridgeEvent(client *WSClient, event ChatBridgeEventMessage) {
	payload, err := json.Marshal(event)
	if err != nil {
		log.Printf("[chat-bridge] marshal event failed: %v", err)
		return
	}
	writeClientText(client, string(payload))
}

func sendDSTAnnouncement(cluster string, text string) error {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := newScriptCommand(ctx, []string{"__announce", cluster, text})
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, cleanForChat(string(output), 1000))
	}
	return nil
}

func displayWorldName(world string) string {
	switch strings.ToLower(strings.TrimSpace(world)) {
	case "master":
		return "地上"
	case "caves":
		return "地下"
	case "shipwrecked":
		return "海难"
	case "volcano":
		return "火山"
	default:
		if strings.TrimSpace(world) == "" {
			return "未知世界"
		}
		return world
	}
}

func buildCLIArgs(message ClientMessage) (string, []string, error) {
	requestedAction, cluster, parsedArgs := parseRequestedAction(message)
	if requestedAction == "" {
		return "", nil, errors.New("缺少 action 或 command")
	}

	action := requestedAction
	if mapped, ok := config.Aliases[requestedAction]; ok {
		action = mapped
	}
	definition, ok := actions[action]
	if !ok {
		return "", nil, fmt.Errorf("不支持的动作: %s", requestedAction)
	}
	if action == "listClusters" {
		return action, []string{"__list_clusters"}, nil
	}

	if cluster == "" {
		var err error
		cluster, err = resolveDefaultCluster()
		if err != nil {
			return "", nil, err
		}
	} else {
		resolved, err := resolveClusterSelector(cluster)
		if err != nil {
			return "", nil, err
		}
		cluster = resolved
	}
	cluster, err := validateCluster(cluster)
	if err != nil {
		return "", nil, err
	}
	args := message.Args
	if args == nil {
		args = map[string]interface{}{}
	}
	for key, value := range parsedArgs {
		if _, exists := args[key]; !exists {
			args[key] = value
		}
	}

	argv, err := definition.BuildArgs(NormalizedInput{Action: action, Cluster: cluster, Args: args})
	return action, argv, err
}

func parseRequestedAction(message ClientMessage) (string, string, map[string]interface{}) {
	cluster := strings.TrimSpace(message.Cluster)
	if action := strings.TrimSpace(message.Action); action != "" {
		return action, cluster, map[string]interface{}{}
	}

	command := strings.TrimSpace(message.Command)
	if command == "" {
		return "", cluster, map[string]interface{}{}
	}

	action, commandCluster, args := parsePlainCommand(command)
	if cluster == "" {
		cluster = commandCluster
	}
	return action, cluster, args
}

func parsePlainCommand(command string) (string, string, map[string]interface{}) {
	if isKnownAction(command) {
		return command, "", map[string]interface{}{}
	}

	parts := strings.Fields(command)
	if len(parts) <= 1 {
		return command, "", map[string]interface{}{}
	}

	if actionAcceptsText(parts[0]) {
		return parts[0], "", map[string]interface{}{actionTextArg(parts[0]): strings.Join(parts[1:], " ")}
	}
	if len(parts) > 2 && actionAcceptsText(parts[1]) {
		return parts[1], parts[0], map[string]interface{}{actionTextArg(parts[1]): strings.Join(parts[2:], " ")}
	}

	first := parts[0]
	tailAction := strings.Join(parts[1:], " ")
	if isKnownAction(tailAction) {
		return tailAction, first, map[string]interface{}{}
	}

	last := parts[len(parts)-1]
	headAction := strings.Join(parts[:len(parts)-1], " ")
	if isKnownAction(headAction) {
		return headAction, last, map[string]interface{}{}
	}

	return command, "", map[string]interface{}{}
}

func isKnownAction(value string) bool {
	value = strings.TrimSpace(value)
	if value == "" {
		return false
	}
	if _, ok := config.Aliases[value]; ok {
		return true
	}
	_, ok := actions[value]
	return ok
}

func canonicalAction(value string) (string, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", false
	}
	if mapped, ok := config.Aliases[value]; ok {
		value = strings.TrimSpace(mapped)
	}
	if _, ok := actions[value]; ok {
		return value, true
	}
	return "", false
}

func actionAcceptsText(value string) bool {
	action, ok := canonicalAction(value)
	return ok && actions[action].TextArg != ""
}

func actionTextArg(value string) string {
	action, ok := canonicalAction(value)
	if !ok {
		return "text"
	}
	if arg := strings.TrimSpace(actions[action].TextArg); arg != "" {
		return arg
	}
	return "text"
}

func resolveDefaultCluster() (string, error) {
	if configured := strings.TrimSpace(config.DefaultCluster); configured != "" && !isAutoClusterSelector(configured) {
		return resolveClusterSelector(configured)
	}

	running, _ := discoverRunningClusters()
	if len(running) == 1 {
		return running[0].Name, nil
	}
	if len(running) > 1 {
		return "", fmt.Errorf("检测到多个运行中存档，请指定存档名或序号。\n%s\n用法：#1 查进程 或 Cluster_1 查进程", formatClusterChoices(running))
	}

	saved, _ := discoverSavedClusters()
	if len(saved) == 1 {
		return saved[0].Name, nil
	}
	if len(saved) > 1 {
		return "", fmt.Errorf("未配置默认存档，且发现多个已保存存档，请指定存档名或序号。\n%s\n用法：#1 开服 或 Cluster_1 开服", formatClusterChoices(saved))
	}

	return "", errors.New("未配置默认存档，也未发现可自动使用的存档。请设置 DST_DEFAULT_CLUSTER，或在命令中指定存档名")
}

func resolveClusterSelector(value string) (string, error) {
	selector := strings.TrimSpace(value)
	if selector == "" || isAutoClusterSelector(selector) {
		return resolveDefaultCluster()
	}
	if isAllClusterSelector(selector) {
		return "", errors.New("暂不支持一次操作全部存档，请用 #序号 或存档名指定一个目标")
	}
	selector = resolveClusterAlias(selector)
	if index, ok := parseClusterIndex(selector); ok {
		clusters := clusterCandidates()
		if index < 1 || index > len(clusters) {
			return "", fmt.Errorf("存档序号 %s 不存在。\n%s", selector, formatClusterChoices(clusters))
		}
		return clusters[index-1].Name, nil
	}
	return selector, nil
}

func resolveClusterAlias(selector string) string {
	current := strings.TrimSpace(selector)
	seen := map[string]bool{}
	for current != "" && !seen[current] {
		seen[current] = true
		next, ok := lookupClusterAlias(current)
		if !ok {
			return current
		}
		current = strings.TrimSpace(next)
	}
	return current
}

func lookupClusterAlias(selector string) (string, bool) {
	if target := strings.TrimSpace(config.ClusterAliases[selector]); target != "" {
		return target, true
	}
	for alias, target := range config.ClusterAliases {
		if strings.EqualFold(strings.TrimSpace(alias), selector) && strings.TrimSpace(target) != "" {
			return strings.TrimSpace(target), true
		}
	}
	return "", false
}

func isAutoClusterSelector(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", "auto", "自动":
		return true
	default:
		return false
	}
}

func isAllClusterSelector(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "*", "all", "全部":
		return true
	default:
		return false
	}
}

func parseClusterIndex(value string) (int, bool) {
	value = strings.TrimSpace(value)
	value = strings.TrimPrefix(value, "#")
	value = strings.TrimPrefix(value, "存档")
	value = strings.TrimPrefix(value, "第")
	if value == "" {
		return 0, false
	}
	index, err := strconv.Atoi(value)
	return index, err == nil
}

func clusterCandidates() []ClusterInfo {
	running, _ := discoverRunningClusters()
	if len(running) > 0 {
		return running
	}
	saved, _ := discoverSavedClusters()
	return saved
}

func connectedMessage() string {
	clusters := clusterCandidates()
	if len(clusters) == 0 {
		if configured := strings.TrimSpace(config.DefaultCluster); configured != "" && !isAutoClusterSelector(configured) {
			return "DST 脚本客户端已连接：" + clusterDisplayLabel(configured)
		}
		return "DST 脚本客户端已连接：未发现存档"
	}
	return "DST 脚本客户端已连接：" + strings.Join(clusterNames(clusters), ", ")
}

func capabilityMessage() string {
	aliasesByAction := map[string][]string{}
	for alias, action := range config.Aliases {
		alias = strings.TrimSpace(alias)
		action = strings.TrimSpace(action)
		if alias == "" || action == "" {
			continue
		}
		aliasesByAction[action] = append(aliasesByAction[action], alias)
	}

	actionNames := make([]string, 0, len(actions))
	for action := range actions {
		actionNames = append(actionNames, action)
	}
	sort.Strings(actionNames)

	capabilities := map[string]ActionCapability{}
	for _, action := range actionNames {
		aliases := aliasesByAction[action]
		sort.Strings(aliases)
		capabilities[action] = ActionCapability{
			Description: actions[action].Description,
			Aliases:     aliases,
			Usage:       actions[action].Usage,
			TextArg:     actions[action].TextArg,
		}
	}

	message := CapabilityMessage{
		Type:           "dst-ws-client.capabilities",
		Version:        1,
		DefaultCluster: config.DefaultCluster,
		Clusters:       clusterCandidates(),
		Actions:        capabilities,
		Aliases:        config.Aliases,
		ClusterAliases: config.ClusterAliases,
	}
	payload, err := json.Marshal(message)
	if err != nil {
		log.Printf("[client] marshal capabilities failed: %v", err)
		return ""
	}
	return string(payload)
}

func formatClusterList() string {
	running, runningErr := discoverRunningClusters()
	saved, savedErr := discoverSavedClusters()
	runningByName := map[string]bool{}
	for _, cluster := range running {
		runningByName[cluster.Name] = true
	}

	lines := []string{"存档列表"}
	if len(running) > 0 {
		lines = append(lines, "运行中：")
		for index, cluster := range running {
			lines = append(lines, fmt.Sprintf("#%d %s%s (%s)", index+1, clusterInfoLabel(cluster), formatClusterAliasSuffix(cluster.Name), strings.Join(cluster.Worlds, ", ")))
		}
	}

	savedOnly := []ClusterInfo{}
	for _, cluster := range saved {
		if !runningByName[cluster.Name] {
			savedOnly = append(savedOnly, cluster)
		}
	}
	if len(savedOnly) > 0 {
		lines = append(lines, "未运行：")
		for _, cluster := range savedOnly {
			lines = append(lines, fmt.Sprintf("- %s%s (%s)", clusterInfoLabel(cluster), formatClusterAliasSuffix(cluster.Name), strings.Join(cluster.Worlds, ", ")))
		}
	}
	if len(running) == 0 && len(savedOnly) == 0 {
		lines = append(lines, "未发现运行中或已保存的 DST 存档。")
	}
	if runningErr != nil {
		lines = append(lines, "运行中存档检测失败："+runningErr.Error())
	}
	if savedErr != nil {
		lines = append(lines, "已保存存档检测失败："+savedErr.Error())
	}
	return strings.Join(lines, "\n")
}

func formatClusterChoices(clusters []ClusterInfo) string {
	if len(clusters) == 0 {
		return "当前未发现可选择的存档。"
	}
	lines := make([]string, 0, len(clusters))
	for index, cluster := range clusters {
		suffix := ""
		if len(cluster.Worlds) > 0 {
			suffix = " (" + strings.Join(cluster.Worlds, ", ") + ")"
		}
		lines = append(lines, fmt.Sprintf("#%d %s%s%s", index+1, clusterInfoLabel(cluster), formatClusterAliasSuffix(cluster.Name), suffix))
	}
	return strings.Join(lines, "\n")
}

func formatClusterAliasSuffix(cluster string) string {
	aliases := aliasesForCluster(cluster)
	if len(aliases) == 0 {
		return ""
	}
	return " [" + strings.Join(aliases, ", ") + "]"
}

func aliasesForCluster(cluster string) []string {
	aliases := []string{}
	for alias, target := range config.ClusterAliases {
		if resolveClusterAlias(target) == cluster {
			aliases = append(aliases, alias)
		}
	}
	sort.Strings(aliases)
	return aliases
}

func clusterNames(clusters []ClusterInfo) []string {
	names := make([]string, 0, len(clusters))
	for _, cluster := range clusters {
		names = append(names, clusterInfoLabel(cluster))
	}
	return names
}

func discoverRunningClusters() ([]ClusterInfo, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, config.Shell, "-lc", "screen -ls 2>/dev/null || true")
	cmd.Dir = config.Cwd
	cmd.Env = os.Environ()
	output, err := cmd.Output()
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if err != nil {
		return nil, err
	}
	return parseScreenClusters(string(output)), nil
}

func parseScreenClusters(output string) []ClusterInfo {
	byName := map[string]*ClusterInfo{}
	for _, line := range strings.Split(output, "\n") {
		session := screenSessionName(line)
		world, cluster, ok := parseDSTScreenSession(session)
		if !ok {
			continue
		}
		info := byName[cluster]
		if info == nil {
			info = &ClusterInfo{Name: cluster, DisplayName: resolveClusterDisplayName(cluster), Running: true}
			byName[cluster] = info
		}
		addWorld(info, world)
	}
	return sortClusters(byName)
}

func screenSessionName(line string) string {
	line = strings.TrimSpace(line)
	dot := strings.Index(line, ".")
	if dot < 0 {
		return ""
	}
	line = line[dot+1:]
	if index := strings.Index(line, "\t("); index >= 0 {
		line = line[:index]
	} else if index := strings.Index(line, " ("); index >= 0 {
		line = line[:index]
	}
	return strings.TrimSpace(line)
}

func parseDSTScreenSession(session string) (string, string, bool) {
	prefixes := []struct {
		Prefix string
		World  string
	}{
		{"DST_Master_beta ", "Master"},
		{"DST_Caves_beta ", "Caves"},
		{"DST_Master ", "Master"},
		{"DST_Caves ", "Caves"},
	}
	for _, item := range prefixes {
		if strings.HasPrefix(session, item.Prefix) {
			cluster := strings.TrimSpace(strings.TrimPrefix(session, item.Prefix))
			return item.World, cluster, cluster != ""
		}
	}
	return "", "", false
}

func discoverSavedClusters() ([]ClusterInfo, error) {
	savePath := detectSavePath()
	entries, err := os.ReadDir(savePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	byName := map[string]*ClusterInfo{}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		name := entry.Name()
		clusterPath := filepath.Join(savePath, name)
		info := &ClusterInfo{Name: name, DisplayName: readClusterDisplayNameFromFile(name)}
		if dirExists(filepath.Join(clusterPath, "Master")) {
			addWorld(info, "Master")
		}
		if dirExists(filepath.Join(clusterPath, "Caves")) {
			addWorld(info, "Caves")
		}
		if len(info.Worlds) > 0 {
			byName[name] = info
		}
	}
	return sortClusters(byName), nil
}

func detectSavePath() string {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	script := fmt.Sprintf("set -- __dst_ws_service; source %s >/dev/null 2>&1; printf '%%s' \"$DST_SAVE_PATH\"", shellQuote(config.ScriptPath))
	cmd := exec.CommandContext(ctx, config.Shell, "-lc", script)
	cmd.Dir = config.Cwd
	cmd.Env = os.Environ()
	output, err := cmd.Output()
	if err == nil {
		if path := strings.TrimSpace(string(output)); path != "" {
			return path
		}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return filepath.Join(".klei", "DoNotStarveTogether")
	}
	return filepath.Join(home, ".klei", "DoNotStarveTogether")
}

func addWorld(info *ClusterInfo, world string) {
	for _, existing := range info.Worlds {
		if existing == world {
			return
		}
	}
	info.Worlds = append(info.Worlds, world)
	sort.Slice(info.Worlds, func(i, j int) bool {
		return worldRank(info.Worlds[i]) < worldRank(info.Worlds[j])
	})
}

func worldRank(world string) int {
	switch world {
	case "Master":
		return 0
	case "Caves":
		return 1
	default:
		return 2
	}
}

func sortClusters(byName map[string]*ClusterInfo) []ClusterInfo {
	clusters := make([]ClusterInfo, 0, len(byName))
	for _, cluster := range byName {
		clusters = append(clusters, *cluster)
	}
	sort.Slice(clusters, func(i, j int) bool {
		return clusters[i].Name < clusters[j].Name
	})
	return clusters
}

func newScriptCommand(ctx context.Context, argv []string) *exec.Cmd {
	var cmd *exec.Cmd
	if len(argv) == 2 && argv[0] == "__status" {
		cluster := argv[1]
		displayCluster := clusterDisplayLabel(cluster)
		script := fmt.Sprintf(
			"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; master='未配置'; caves='未配置'; if [ -d \"$DST_SAVE_PATH/%s/Master\" ]; then if screen -ls | grep --text -q \"\\<$process_name_master\\>\"; then master='运行中'; else master='未运行'; fi; fi; if [ -d \"$DST_SAVE_PATH/%s/Caves\" ]; then if screen -ls | grep --text -q \"\\<$process_name_caves\\>\"; then caves='运行中'; else caves='未运行'; fi; fi; printf '存档: %s\\n地上: %s\\n地下: %s\\n' %s \"$master\" \"$caves\"",
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellEscapeForDoubleQuoted(cluster),
			shellEscapeForDoubleQuoted(cluster),
			"%s",
			"%s",
			"%s",
			shellQuote(displayCluster),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) == 2 && argv[0] == "__source_close_server" {
		cluster := argv[1]
		script := fmt.Sprintf(
			"set -- __dst_ws_service; source %s; init %s; close_server %s -close",
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellQuote(cluster),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) == 2 && argv[0] == "__start_server" {
		cluster := argv[1]
		displayCluster := clusterDisplayLabel(cluster)
		script := fmt.Sprintf(
			"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; get_process_name %s; master='未运行'; caves='未运行'; if [ -n \"${process_name_master:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_master\\>\"; then master='运行中'; fi; if [ -n \"${process_name_caves:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_caves\\>\"; then caves='运行中'; fi; if [ \"$master\" = '运行中' ] || [ \"$caves\" = '运行中' ]; then printf '服务器已开启：%s\\n地上：%%s\\n地下：%%s\\n' \"$master\" \"$caves\"; exit 0; fi; if [ -n \"${process_name_AutoUpdate:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_AutoUpdate\\>\"; then echo \"守护进程已运行：$process_name_AutoUpdate\"; else get_path_script_files %s; screen -dmS \"$process_name_AutoUpdate\" /bin/sh -c \"$script_files_path/auto_update.sh\"; echo \"守护进程已启动：$process_name_AutoUpdate\"; fi; timeout --kill-after=5s 75s bash -lc %s; rc=$?; source %s >/dev/null; init %s >/dev/null; get_process_name %s; master='未运行'; caves='未运行'; if [ -n \"${process_name_master:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_master\\>\"; then master='运行中'; fi; if [ -n \"${process_name_caves:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_caves\\>\"; then caves='运行中'; fi; printf '\\n状态确认：地上 %%s\\n状态确认：地下 %%s\\n' \"$master\" \"$caves\"; if [ \"$master\" = '运行中' ] || [ \"$caves\" = '运行中' ]; then exit 0; fi; exit \"$rc\"",
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellQuote(cluster),
			shellEscapeForDoubleQuoted(displayCluster),
			shellQuote(cluster),
			shellQuote("source "+shellQuote(config.ScriptPath)+" >/dev/null; init "+shellQuote(cluster)+" >/dev/null; howtostart "+shellQuote(cluster)+" -AUTO"),
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellQuote(cluster),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) >= 2 && len(argv) <= 3 && argv[0] == "-restart_server" {
		cluster := argv[1]
		restartArgs := shellQuote(config.ScriptPath) + " -restart_server " + shellQuote(cluster)
		if len(argv) == 3 {
			restartArgs += " " + shellQuote(argv[2])
		}
		script := fmt.Sprintf(
			"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; get_process_name %s; if [ -n \"${process_name_AutoUpdate:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_AutoUpdate\\>\"; then echo \"守护进程已运行：$process_name_AutoUpdate\"; else get_path_script_files %s; screen -dmS \"$process_name_AutoUpdate\" /bin/sh -c \"$script_files_path/auto_update.sh\"; echo \"守护进程已启动：$process_name_AutoUpdate\"; fi; timeout --kill-after=5s 75s %s; rc=$?; source %s >/dev/null; init %s >/dev/null; get_process_name %s; master='未运行'; caves='未运行'; if [ -n \"${process_name_master:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_master\\>\"; then master='运行中'; fi; if [ -n \"${process_name_caves:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_caves\\>\"; then caves='运行中'; fi; printf '\\n状态确认：地上 %%s\\n状态确认：地下 %%s\\n' \"$master\" \"$caves\"; if [ \"$master\" = '运行中' ] || [ \"$caves\" = '运行中' ]; then exit 0; fi; exit \"$rc\"",
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellQuote(cluster),
			shellQuote(cluster),
			restartArgs,
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellQuote(cluster),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) == 3 && argv[0] == "__console_rollback" {
		cluster := argv[1]
		days := argv[2]
		script := fmt.Sprintf(
			"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; get_process_name %s; target=''; if [ -n \"${process_name_master:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_master\\>\"; then target=\"$process_name_master\"; elif [ -n \"${process_name_main:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_main\\>\"; then target=\"$process_name_main\"; elif [ -n \"${process_name_caves:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_caves\\>\"; then target=\"$process_name_caves\"; fi; if [ -z \"$target\" ]; then echo \"服务器进程未运行，无法回档\"; exit 1; fi; screen -S \"$target\" -p 0 -X stuff \"c_rollback(%s)$(printf '\\r')\"; echo \"已发送回档%s天命令到 $target\"",
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellQuote(cluster),
			days,
			days,
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) == 2 && argv[0] == "__mod_info" {
		cluster := argv[1]
		displayCluster := clusterDisplayLabel(cluster)
		script := fmt.Sprintf(
			`set -- __dst_ws_service
source %s >/dev/null
init %s >/dev/null
base="$DST_SAVE_PATH/%s"
echo "模组信息 - %s"
declare -A worlds
found_file=0
for world in Master Caves; do
	file="$base/$world/modoverrides.lua"
	[ -f "$file" ] || continue
	found_file=1
	while IFS= read -r mod; do
		id="${mod#workshop-}"
		[ -n "$id" ] || continue
		if [ -n "${worlds[$id]:-}" ]; then
			case ",${worlds[$id]}," in
				*",$world,"*) ;;
				*) worlds[$id]="${worlds[$id]},$world" ;;
			esac
		else
			worlds[$id]="$world"
		fi
	done < <(grep -aoE 'workshop-[0-9]+' "$file" | sort -u)
done
if [ "$found_file" -ne 1 ]; then
	echo "未找到 modoverrides.lua"
	exit 1
fi
if [ "${#worlds[@]}" -eq 0 ]; then
	echo "未配置 Workshop 模组"
	exit 0
fi
mapfile -t ids < <(for id in "${!worlds[@]}"; do echo "$id"; done | sort -n)
echo "已配置 ${#ids[@]} 个 Workshop 模组"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
chunk_size=5
parallel_limit=4
running=0
chunk_index=0
for ((offset=0; offset<${#ids[@]}; offset+=chunk_size)); do
	(
		data="itemcount=0"
		count=0
		for ((i=offset; i<${#ids[@]} && i<offset+chunk_size; i++)); do
			data="itemcount=$((count + 1))${data#itemcount=$count}"
			data="$data&publishedfileids[$count]=${ids[$i]}"
			count=$((count + 1))
		done
		for attempt in 1 2 3; do
			response=$(curl -s --connect-timeout 8 --max-time 15 -X POST 'http://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -H 'Content-Type: application/x-www-form-urlencoded' --data "$data")
			if echo "$response" | jq -e '.response.publishedfiledetails' >/dev/null 2>&1; then
				echo "$response" | jq -r '.response.publishedfiledetails[] | [.publishedfileid, (.title // ""), (([.tags[]? | .tag | select(startswith("version:"))][0] // "") | sub("^version:"; "")), (.result // 0 | tostring)] | @tsv' > "$tmp_dir/chunk-$offset.tsv"
				exit 0
			fi
			sleep 1
		done
		exit 0
	) &
	running=$((running + 1))
	chunk_index=$((chunk_index + 1))
	if [ "$running" -ge "$parallel_limit" ]; then
		wait -n || true
		running=$((running - 1))
	fi
done
wait || true
cat "$tmp_dir"/chunk-*.tsv > "$tmp_dir/all.tsv" 2>/dev/null || true
for id in "${ids[@]}"; do
	line=$(grep -m 1 "^$id"$'\t' "$tmp_dir/all.tsv" 2>/dev/null || true)
	if [ -n "$line" ]; then
		IFS=$'\t' read -r id title version result <<< "$line"
	else
		title=""
		version=""
		result="0"
	fi
	[ -n "$id" ] || continue
	if [ "$result" != "1" ]; then
		echo "- workshop-$id"
		echo "  ID：workshop-$id | 版本：未知 | 世界：${worlds[$id]}"
		continue
	fi
	[ -n "$title" ] || title="未命名模组"
	[ -n "$version" ] || version="未标注"
	echo "- $title"
	echo "  ID：workshop-$id | 版本：$version | 世界：${worlds[$id]}"
done`,
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellEscapeForDoubleQuoted(cluster),
			shellEscapeForDoubleQuoted(displayCluster),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) == 2 && argv[0] == "__world_info" {
		cluster := argv[1]
		displayCluster := clusterDisplayLabel(cluster)
		script := fmt.Sprintf(
			"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; base=\"$DST_SAVE_PATH/%s\"; echo \"World info: %s\"; if [ -f \"$base/cluster.ini\" ]; then echo; echo \"[cluster.ini]\"; sed -n '1,120p' \"$base/cluster.ini\"; fi; found=0; for world in Master Caves; do file=\"$base/$world/leveldataoverride.lua\"; [ -f \"$file\" ] || continue; found=1; echo; echo \"[$world leveldataoverride.lua]\"; sed -n '1,180p' \"$file\"; done; if [ \"$found\" -ne 1 ]; then echo \"no leveldataoverride.lua found\"; exit 1; fi",
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellEscapeForDoubleQuoted(cluster),
			shellEscapeForDoubleQuoted(displayCluster),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) == 2 && argv[0] == "__runtime_world_info" {
		cluster := argv[1]
		displayCluster := clusterDisplayLabel(cluster)
		script := fmt.Sprintf(
			`set -- __dst_ws_service
source %s >/dev/null
init %s >/dev/null
get_process_name %s
if ! screen -ls | grep --text -Eq "\<(${process_name_master:-__none__}|${process_name_caves:-__none__}|${process_name_main:-__none__})\>"; then
	echo "服务器进程未运行，无法获取运行时世界信息"
	exit 1
fi
getworldstate
getmonster
n(){ if [ -n "$1" ]; then printf '%%s' "$1"; else printf '0'; fi; }
current_version=""
[ -f "$gamesPath/version.txt" ] && current_version=$(tr -d '[:space:]' < "$gamesPath/version.txt")
current_buildid=$(grep --text -m 1 '"buildid"' "$gamesPath/steamapps/appmanifest_343050.acf" 2>/dev/null | sed 's/[^0-9]//g')
latest_version="未知"
version_status="无法检查"
if [ -n "$current_version" ]; then
	response=$(curl -s --connect-timeout 8 --max-time 15 "http://api.steampowered.com/ISteamApps/UpToDateCheck/v1/?appid=322330&version=${current_version}" || true)
	if command -v jq >/dev/null 2>&1 && echo "$response" | jq -e '.response.success == true' >/dev/null 2>&1; then
		up_to_date=$(echo "$response" | jq -r '.response.up_to_date')
		if [ "$up_to_date" = "true" ]; then
			latest_version="$current_version"
			version_status="已是最新"
		elif [ "$up_to_date" = "false" ]; then
			latest_version="Steam 已有更新"
			version_status="需要更新"
		else
			version_status="Steam 返回异常"
		fi
	else
		version_status="Steam 检查失败"
	fi
fi
echo "世界信息 - %s"
echo "版本：当前 ${current_version:-未知} | 最新 $latest_version | 状态 $version_status | buildid ${current_buildid:-未知}"
echo "状态：第$(n "$presentcycles")天，$presentseason 第$(n "$presentday")天，$presentphase / $presentmoonphase / $presentrain / $presentsnow / $(n "$presenttemperature")°C"
if screen -ls | grep --text -q "\<$process_name_master\>"; then
	echo ""
	echo "地上："
	echo "海象巢 $(n "$walrus_camp_master") | 高脚鸟巢 $(n "$tallbirdnest_master") | 猎犬丘 $(n "$houndmound_master") | 墓地 $(n "$gravestone_master")"
	echo "触手怪 $(n "$tentacle_master") | 蜘蛛巢 $(n "$spiderden_master") | 芦苇 $(n "$reeds_master") 株"
fi
if screen -ls | grep --text -q "\<$process_name_caves\>"; then
	echo ""
	echo "地下："
	echo "触手怪 $(n "$tentacle_caves") | 蜘蛛巢 $(n "$spiderden_caves") | 芦苇 $(n "$reeds_caves") 株"
	echo "损坏主教 $(n "$bishop_nightmare") | 损坏战车 $(n "$rook_nightmare") | 损坏骑士 $(n "$knight_nightmare")"
fi`,
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellQuote(cluster),
			shellEscapeForDoubleQuoted(displayCluster),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) == 2 && argv[0] == "__chat_log" {
		cluster := argv[1]
		displayCluster := clusterDisplayLabel(cluster)
		script := fmt.Sprintf(
			"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; base=\"$DST_SAVE_PATH/%s\"; echo \"Recent chat log: %s\"; found=0; for world in Master Caves Shipwrecked Volcano; do file=\"$base/$world/server_chat_log.txt\"; [ -f \"$file\" ] || continue; found=1; echo; echo \"[$world]\"; tail -n 80 \"$file\"; break; done; if [ \"$found\" -ne 1 ]; then echo \"no server_chat_log.txt found\"; exit 1; fi",
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellEscapeForDoubleQuoted(cluster),
			shellEscapeForDoubleQuoted(displayCluster),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else if len(argv) == 3 && argv[0] == "__announce" {
		cluster := argv[1]
		text := argv[2]
		consoleCommand := "c_announce(" + luaLongString(text) + ")"
		script := fmt.Sprintf(
			"set -- __dst_ws_service; source %s >/dev/null; init %s >/dev/null; get_process_name %s; target=''; if [ -n \"${process_name_master:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_master\\>\"; then target=\"$process_name_master\"; elif [ -n \"${process_name_main:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_main\\>\"; then target=\"$process_name_main\"; elif [ -n \"${process_name_caves:-}\" ] && screen -ls | grep --text -q \"\\<$process_name_caves\\>\"; then target=\"$process_name_caves\"; fi; if [ -z \"$target\" ]; then echo \"server is not running, cannot announce\"; exit 1; fi; command=%s; screen -S \"$target\" -p 0 -X stuff \"$command$(printf '\\r')\"; echo \"sent announce to $target: %s\"",
			shellQuote(config.ScriptPath),
			shellQuote(cluster),
			shellQuote(cluster),
			shellQuote(consoleCommand),
			shellEscapeForDoubleQuoted(text),
		)
		cmd = exec.CommandContext(ctx, config.Shell, "-lc", script)
	} else {
		cmd = exec.CommandContext(ctx, config.Shell, append([]string{config.ScriptPath}, argv...)...)
	}
	cmd.Dir = config.Cwd
	cmd.Env = os.Environ()
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	return cmd
}

func shellEscapeForDoubleQuoted(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, `"`, `\"`)
	value = strings.ReplaceAll(value, `$`, `\$`)
	value = strings.ReplaceAll(value, "`", "\\`")
	return value
}

func luaLongString(value string) string {
	level := 0
	for {
		equals := strings.Repeat("=", level)
		close := "]" + equals + "]"
		if !strings.Contains(value, close) {
			return "[" + equals + "[" + value + close
		}
		level++
	}
}

func killCommandGroup(cmd *exec.Cmd) {
	if cmd == nil || cmd.Process == nil {
		return
	}
	pgid, err := syscall.Getpgid(cmd.Process.Pid)
	if err != nil {
		return
	}
	_ = syscall.Kill(-pgid, syscall.SIGKILL)
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func readFrameFrom(reader io.Reader, requireMasked bool) (byte, []byte, error) {
	header := make([]byte, 2)
	if _, err := io.ReadFull(reader, header); err != nil {
		return 0, nil, err
	}

	opcode := header[0] & 0x0F
	masked := header[1]&0x80 != 0
	length := uint64(header[1] & 0x7F)

	if length == 126 {
		extended := make([]byte, 2)
		if _, err := io.ReadFull(reader, extended); err != nil {
			return 0, nil, err
		}
		length = uint64(binary.BigEndian.Uint16(extended))
	} else if length == 127 {
		extended := make([]byte, 8)
		if _, err := io.ReadFull(reader, extended); err != nil {
			return 0, nil, err
		}
		length = binary.BigEndian.Uint64(extended)
	}

	if requireMasked && !masked {
		return 0, nil, errors.New("客户端 WebSocket frame 必须 masked")
	}
	if length > maxFramePayload {
		return 0, nil, errors.New("WebSocket frame 太大")
	}

	var mask []byte
	if masked {
		mask = make([]byte, 4)
		if _, err := io.ReadFull(reader, mask); err != nil {
			return 0, nil, err
		}
	}
	payload := make([]byte, int(length))
	if _, err := io.ReadFull(reader, payload); err != nil {
		return 0, nil, err
	}
	if masked {
		for index := range payload {
			payload[index] ^= mask[index%4]
		}
	}

	return opcode, payload, nil
}

func writeClientText(client *WSClient, text string) {
	wsWriteMu.Lock()
	defer wsWriteMu.Unlock()
	if err := writeClientFrame(client, 0x1, []byte(text)); err != nil {
		log.Printf("[client] write failed: %v", err)
	}
}

func writeClientFrame(client *WSClient, opcode byte, payload []byte) error {
	client.Mu.Lock()
	defer client.Mu.Unlock()
	if err := client.Conn.SetWriteDeadline(time.Now().Add(clientWriteTimeout)); err != nil {
		return err
	}
	defer func() {
		_ = client.Conn.SetWriteDeadline(time.Time{})
	}()
	return writeFrameMasked(client.Conn, opcode, payload)
}

func writeFrameMasked(writer io.Writer, opcode byte, payload []byte) error {
	header := []byte{0x80 | opcode, 0x80}
	length := len(payload)
	if length < 126 {
		header[1] |= byte(length)
	} else if length <= 65535 {
		header = make([]byte, 4)
		header[0] = 0x80 | opcode
		header[1] = 0x80 | 126
		binary.BigEndian.PutUint16(header[2:], uint16(length))
	} else {
		header = make([]byte, 10)
		header[0] = 0x80 | opcode
		header[1] = 0x80 | 127
		binary.BigEndian.PutUint64(header[2:], uint64(length))
	}
	mask := make([]byte, 4)
	if _, err := rand.Read(mask); err != nil {
		return err
	}
	masked := make([]byte, len(payload))
	for index := range payload {
		masked[index] = payload[index] ^ mask[index%4]
	}
	if _, err := writer.Write(header); err != nil {
		return err
	}
	if _, err := writer.Write(mask); err != nil {
		return err
	}
	_, err := writer.Write(masked)
	return err
}

func acceptKey(key string) string {
	sum := sha1.Sum([]byte(key + websocketGUID))
	return base64.StdEncoding.EncodeToString(sum[:])
}

func dialWebSocket(rawURL string) (*WSClient, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	if parsed.Scheme != "ws" && parsed.Scheme != "wss" {
		return nil, fmt.Errorf("upstreamUrl scheme 必须是 ws 或 wss: %s", parsed.Scheme)
	}
	host := parsed.Host
	if !strings.Contains(host, ":") {
		if parsed.Scheme == "wss" {
			host = net.JoinHostPort(host, "443")
		} else {
			host = net.JoinHostPort(host, "80")
		}
	}

	dialer := net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second}
	var conn net.Conn
	if parsed.Scheme == "wss" {
		conn, err = tls.DialWithDialer(&dialer, "tcp", host, &tls.Config{ServerName: parsed.Hostname(), MinVersion: tls.VersionTLS12})
	} else {
		conn, err = dialer.Dial("tcp", host)
	}
	if err != nil {
		return nil, err
	}

	keyBytes := make([]byte, 16)
	if _, err := rand.Read(keyBytes); err != nil {
		_ = conn.Close()
		return nil, err
	}
	key := base64.StdEncoding.EncodeToString(keyBytes)
	requestURI := parsed.RequestURI()
	if requestURI == "" {
		requestURI = "/"
	}
	req, err := http.NewRequest(http.MethodGet, requestURI, nil)
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	req.Host = parsed.Host
	req.Header.Set("Upgrade", "websocket")
	req.Header.Set("Connection", "Upgrade")
	req.Header.Set("Sec-WebSocket-Key", key)
	req.Header.Set("Sec-WebSocket-Version", "13")
	req.Header.Set("User-Agent", "dst-ws-client")
	if err := req.Write(conn); err != nil {
		_ = conn.Close()
		return nil, err
	}

	reader := bufio.NewReader(conn)
	resp, err := http.ReadResponse(reader, req)
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusSwitchingProtocols {
		_ = conn.Close()
		return nil, fmt.Errorf("websocket upgrade failed: %s", resp.Status)
	}
	if !strings.EqualFold(resp.Header.Get("Sec-WebSocket-Accept"), acceptKey(key)) {
		_ = conn.Close()
		return nil, errors.New("websocket accept key 校验失败")
	}
	return &WSClient{Conn: conn, R: reader}, nil
}

func upstreamURLWithToken(rawURL string) string {
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Query().Get("token") != "" || config.Token == "" {
		return rawURL
	}
	query := parsed.Query()
	query.Set("token", config.Token)
	parsed.RawQuery = query.Encode()
	return parsed.String()
}

func redactedURL(rawURL string) string {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return rawURL
	}
	query := parsed.Query()
	if query.Get("token") != "" {
		query.Set("token", "REDACTED")
		parsed.RawQuery = query.Encode()
	}
	return parsed.String()
}

func validateCluster(value string) (string, error) {
	cluster := strings.TrimSpace(value)
	if cluster == "" {
		return "", errors.New("cluster 不能为空")
	}
	if strings.Contains(cluster, "/") || strings.Contains(cluster, "\\") || strings.Contains(cluster, "\x00") || strings.Contains(cluster, "..") {
		return "", fmt.Errorf("cluster 不能包含路径字符: %s", cluster)
	}
	return cluster, nil
}

func optionalChoice(value interface{}, field string, choices []string) (string, error) {
	if value == nil {
		return "", nil
	}
	text := fmt.Sprint(value)
	for _, choice := range choices {
		if text == choice {
			return text, nil
		}
	}
	return "", fmt.Errorf("%s 只能是: %s", field, strings.Join(nonEmpty(choices), ", "))
}

func requiredText(value interface{}, field string) (string, error) {
	if value == nil {
		return "", fmt.Errorf("%s 不能为空", field)
	}
	text := strings.TrimSpace(fmt.Sprint(value))
	if text == "" || text == "<nil>" {
		return "", fmt.Errorf("%s 不能为空", field)
	}
	if strings.Contains(text, "\x00") || strings.Contains(text, "\r") || strings.Contains(text, "\n") {
		return "", fmt.Errorf("%s 不能包含换行或 NUL 字符", field)
	}
	return text, nil
}

func requiredPositiveInt(value interface{}, field string) (int, error) {
	text, err := requiredText(value, field)
	if err != nil {
		return 0, fmt.Errorf("请输入要%s，例如：回档 3", field)
	}
	days, err := strconv.Atoi(text)
	if err != nil || days <= 0 {
		return 0, fmt.Errorf("%s必须是大于 0 的整数，例如：回档 3", field)
	}
	return days, nil
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}

func findConfigPath() string {
	args := os.Args[1:]
	for index := 0; index < len(args); index++ {
		if args[index] == "--config" && index+1 < len(args) {
			return absOrDie(args[index+1])
		}
		if strings.HasPrefix(args[index], "--config=") {
			return absOrDie(strings.TrimPrefix(args[index], "--config="))
		}
	}
	if value := os.Getenv("DST_WS_CONFIG"); value != "" {
		return absOrDie(value)
	}
	return defaultConfigPath()
}

func defaultConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return absOrDie(filepath.Join(".dst-ws-client", "config.json"))
	}
	return filepath.Join(home, ".dst-ws-client", "config.json")
}

func resolvePath(value string) (string, error) {
	if filepath.IsAbs(value) {
		return filepath.Clean(value), nil
	}
	return filepath.Abs(value)
}

func absOrDie(value string) string {
	path, err := resolvePath(value)
	if err != nil {
		log.Fatal(err)
	}
	return path
}

func parseClusterAliases(value string) (map[string]string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return map[string]string{}, nil
	}
	if strings.HasPrefix(value, "{") {
		aliases := map[string]string{}
		if err := json.Unmarshal([]byte(value), &aliases); err != nil {
			return nil, fmt.Errorf("DST_CLUSTER_ALIASES JSON 无效: %w", err)
		}
		return aliases, nil
	}

	aliases := map[string]string{}
	items := strings.FieldsFunc(value, func(r rune) bool {
		return r == ',' || r == ';' || r == '\n'
	})
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		separator := strings.Index(item, "=")
		if separator < 0 {
			separator = strings.Index(item, ":")
		}
		if separator < 0 {
			return nil, fmt.Errorf("DST_CLUSTER_ALIASES 项必须是 别名=存档名: %s", item)
		}
		alias := strings.TrimSpace(item[:separator])
		cluster := strings.TrimSpace(item[separator+1:])
		if alias == "" || cluster == "" {
			return nil, fmt.Errorf("DST_CLUSTER_ALIASES 项不能为空: %s", item)
		}
		aliases[alias] = cluster
	}
	return aliases, nil
}

func nonEmpty(values []string) []string {
	result := []string{}
	for _, value := range values {
		if value != "" {
			result = append(result, value)
		}
	}
	return result
}

func cleanForChat(text string, limit int) string {
	text = ansiPattern.ReplaceAllString(text, "")
	text = strings.ReplaceAll(text, "\r", "\n")
	lines := strings.Split(text, "\n")
	cleaned := make([]string, 0, len(lines))
	last := ""
	blank := false
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			if !blank {
				cleaned = append(cleaned, "")
			}
			blank = true
			continue
		}
		blank = false
		if line == last {
			continue
		}
		cleaned = append(cleaned, line)
		last = line
	}
	result := strings.TrimSpace(strings.Join(cleaned, "\n"))
	runes := []rune(result)
	if len(runes) <= limit {
		return result
	}
	omitted := len(runes) - limit
	return fmt.Sprintf("... 已省略前 %d 字符 ...\n%s", omitted, string(runes[len(runes)-limit:]))
}

func getenvDefault(key string, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
