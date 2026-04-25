package main

import (
	"bytes"
	"flag"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/charmbracelet/bubbles/textarea"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type config struct {
	cmuxPath    string
	socketPath  string
	password    string
	basePath    string
	name        string
	prompt      string
	imagePaths  []string
	jsonOutput  bool
	useAIName   bool
	claudeCount int
	codexCount  int
	openCount   int
}

type stringList []string

type imageAttachment struct {
	Token string
	Path  string
	Name  string
}

type focusMode int

const (
	focusPrompt focusMode = iota
	focusAgents
)

type model struct {
	cfg           config
	textarea      textarea.Model
	width         int
	height        int
	focus         focusMode
	selectedAgent int
	images        []imageAttachment
	status        string
	statusKind    string
	launching     bool
}

type launchDoneMsg struct {
	output string
	err    error
}

type tokenRange struct {
	rawStart int
	rawEnd   int
	value    string
}

var imageTokenRE = regexp.MustCompile(`\[Image #[0-9]+\]`)

var imageExtensions = map[string]bool{
	".avif": true,
	".bmp":  true,
	".gif":  true,
	".heic": true,
	".heif": true,
	".jpeg": true,
	".jpg":  true,
	".png":  true,
	".tif":  true,
	".tiff": true,
	".webp": true,
}

var (
	green     = lipgloss.Color("46")
	dimGreen  = lipgloss.Color("29")
	amber     = lipgloss.Color("214")
	red       = lipgloss.Color("203")
	screenBG  = lipgloss.Color("0")
	frame     = lipgloss.NewStyle().Foreground(green).Background(screenBG).Border(lipgloss.NormalBorder()).BorderForeground(green).Padding(1, 3)
	title     = lipgloss.NewStyle().Foreground(green).Bold(true).Align(lipgloss.Center)
	subtle    = lipgloss.NewStyle().Foreground(dimGreen)
	hot       = lipgloss.NewStyle().Foreground(amber).Bold(true)
	errorText = lipgloss.NewStyle().Foreground(red)
)

func main() {
	cfg := parseConfig()
	m := initialModel(cfg)
	if _, err := tea.NewProgram(m, tea.WithAltScreen()).Run(); err != nil {
		fmt.Fprintf(os.Stderr, "cmux-agent-launcher-tui: %v\n", err)
		os.Exit(1)
	}
}

func parseConfig() config {
	cfg := config{
		cmuxPath:    "cmux",
		useAIName:   true,
		claudeCount: 1,
		codexCount:  1,
		openCount:   0,
	}
	var imagePaths stringList
	flag.StringVar(&cfg.cmuxPath, "cmux", cfg.cmuxPath, "cmux executable path")
	flag.StringVar(&cfg.socketPath, "socket", "", "cmux socket path")
	flag.StringVar(&cfg.password, "password", "", "cmux socket password")
	flag.StringVar(&cfg.basePath, "base", "", "repo or hq path")
	flag.StringVar(&cfg.name, "name", "", "workspace name")
	flag.StringVar(&cfg.prompt, "prompt", "", "initial prompt")
	flag.Var(&imagePaths, "image", "initial image path")
	flag.IntVar(&cfg.claudeCount, "claude", cfg.claudeCount, "Claude pane count")
	flag.IntVar(&cfg.codexCount, "codex", cfg.codexCount, "Codex pane count")
	flag.IntVar(&cfg.openCount, "opencode", cfg.openCount, "OpenCode pane count")
	flag.BoolVar(&cfg.jsonOutput, "json", false, "request JSON backend output")
	noAIName := flag.Bool("no-ai-name", false, "disable AI workspace name generation")
	flag.Parse()
	cfg.useAIName = !*noAIName
	cfg.claudeCount = clampInt(cfg.claudeCount, 0, 8)
	cfg.codexCount = clampInt(cfg.codexCount, 0, 8)
	cfg.openCount = clampInt(cfg.openCount, 0, 8)
	cfg.imagePaths = append([]string(nil), imagePaths...)
	return cfg
}

func (l *stringList) String() string {
	if l == nil {
		return ""
	}
	return strings.Join(*l, ",")
}

func (l *stringList) Set(value string) error {
	*l = append(*l, value)
	return nil
}

func initialModel(cfg config) model {
	ta := textarea.New()
	ta.Placeholder = "Drop a screenshot, paste context, then press ctrl+r"
	ta.Prompt = "  "
	ta.ShowLineNumbers = false
	ta.CharLimit = 20000
	ta.SetWidth(68)
	ta.SetHeight(8)
	ta.FocusedStyle.CursorLine = lipgloss.NewStyle()
	ta.FocusedStyle.Prompt = lipgloss.NewStyle().Foreground(green)
	ta.FocusedStyle.Text = lipgloss.NewStyle().Foreground(green)
	ta.FocusedStyle.Placeholder = lipgloss.NewStyle().Foreground(dimGreen)
	ta.FocusedStyle.Base = lipgloss.NewStyle().Foreground(green)
	ta.BlurredStyle = ta.FocusedStyle
	ta.Focus()

	m := model{
		cfg:      cfg,
		textarea: ta,
		status:   "ready",
	}
	if strings.TrimSpace(cfg.prompt) != "" {
		m.textarea.SetValue(cfg.prompt)
	}
	for _, rawPath := range cfg.imagePaths {
		path, ok := normalizeImagePath(rawPath)
		if !ok {
			continue
		}
		token := m.imageTokenForPath(path)
		if !strings.Contains(m.textarea.Value(), token) {
			if strings.TrimSpace(m.textarea.Value()) != "" {
				m.textarea.InsertString(" ")
			}
			m.textarea.InsertString(token)
		}
	}
	return m
}

func (m model) Init() tea.Cmd {
	return textarea.Blink
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.resize(msg.Width, msg.Height)
		return m, nil
	case launchDoneMsg:
		m.launching = false
		if msg.err != nil {
			m.statusKind = "error"
			m.status = strings.TrimSpace(msg.output)
			if m.status == "" {
				m.status = msg.err.Error()
			}
			return m, nil
		}
		m.statusKind = "ok"
		m.status = firstNonEmptyLine(msg.output)
		if m.status == "" {
			m.status = "workspace created"
		}
		m.textarea.Reset()
		m.images = nil
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "ctrl+r":
			return m.startLaunch()
		case "tab":
			m.toggleFocus()
			return m, nil
		}

		if m.launching {
			return m, nil
		}

		if m.focus == focusAgents {
			switch msg.String() {
			case "left", "h":
				m.selectedAgent = (m.selectedAgent + 2) % 3
			case "right", "l":
				m.selectedAgent = (m.selectedAgent + 1) % 3
			case "up", "k", "+", "=":
				m.adjustSelectedAgent(1)
			case "down", "j", "-":
				m.adjustSelectedAgent(-1)
			case "enter", "esc":
				m.focus = focusPrompt
				cmd = m.textarea.Focus()
			}
			return m, cmd
		}

		if msg.Type == tea.KeyRunes && len(msg.Runes) > 0 {
			replacement, changed := m.replaceImagePaths(string(msg.Runes))
			if changed {
				m.textarea.InsertString(replacement)
				m.normalizeImageTokenCursor("right")
				m.statusKind = "ok"
				m.status = fmt.Sprintf("attached %d image%s", len(m.images), plural(len(m.images)))
				return m, nil
			}
		}
		m.textarea, cmd = m.textarea.Update(msg)
		switch msg.String() {
		case "left", "ctrl+b", "alt+left":
			m.normalizeImageTokenCursor("left")
		case "right", "ctrl+f", "alt+right":
			m.normalizeImageTokenCursor("right")
		}
		return m, cmd
	}

	m.textarea, cmd = m.textarea.Update(msg)
	return m, cmd
}

func (m *model) resize(width, height int) {
	m.width = width
	m.height = height
	boxWidth := clampInt(width-10, 68, 102)
	textWidth := clampInt(boxWidth-12, 44, 90)
	textHeight := clampInt(height/3, 6, 11)
	m.textarea.SetWidth(textWidth)
	m.textarea.SetHeight(textHeight)
}

func (m *model) toggleFocus() {
	if m.focus == focusPrompt {
		m.focus = focusAgents
		m.textarea.Blur()
		return
	}
	m.focus = focusPrompt
	m.textarea.Focus()
}

func (m *model) adjustSelectedAgent(delta int) {
	switch m.selectedAgent {
	case 0:
		m.cfg.claudeCount = clampInt(m.cfg.claudeCount+delta, 0, 8)
	case 1:
		m.cfg.codexCount = clampInt(m.cfg.codexCount+delta, 0, 8)
	case 2:
		m.cfg.openCount = clampInt(m.cfg.openCount+delta, 0, 8)
	}
}

func (m model) startLaunch() (tea.Model, tea.Cmd) {
	prompt := strings.TrimSpace(m.textarea.Value())
	if prompt == "" && len(m.images) == 0 {
		m.statusKind = "error"
		m.status = "write a prompt or attach an image first"
		return m, nil
	}
	if m.cfg.claudeCount+m.cfg.codexCount+m.cfg.openCount == 0 {
		m.cfg.claudeCount = 1
		m.cfg.codexCount = 1
	}
	m.launching = true
	m.statusKind = ""
	m.status = "creating worktrees and workspace..."
	cfg := m.cfg
	images := append([]imageAttachment(nil), m.images...)
	return m, func() tea.Msg {
		args := []string{}
		if cfg.socketPath != "" {
			args = append(args, "--socket", cfg.socketPath)
		}
		if cfg.password != "" {
			args = append(args, "--password", cfg.password)
		}
		if cfg.jsonOutput {
			args = append(args, "--json")
		}
		args = append(args,
			"agent-launcher", "run",
			"--prompt", prompt,
			"--claude", strconv.Itoa(cfg.claudeCount),
			"--codex", strconv.Itoa(cfg.codexCount),
			"--opencode", strconv.Itoa(cfg.openCount),
		)
		if cfg.basePath != "" {
			args = append(args, "--base", cfg.basePath)
		}
		if cfg.name != "" {
			args = append(args, "--name", cfg.name)
		}
		if !cfg.useAIName {
			args = append(args, "--no-ai-name")
		}
		for _, image := range images {
			args = append(args, "--image", image.Path)
		}
		cmd := exec.Command(cfg.cmuxPath, args...)
		var output bytes.Buffer
		cmd.Stdout = &output
		cmd.Stderr = &output
		err := cmd.Run()
		return launchDoneMsg{output: output.String(), err: err}
	}
}

func (m model) View() string {
	if m.width == 0 || m.height == 0 {
		return ""
	}

	boxWidth := clampInt(m.width-10, 68, 102)
	header := title.Width(boxWidth - 8).Render("CMUX HOME")
	subheader := subtle.Width(boxWidth - 8).Align(lipgloss.Center).Render("agent workspace launcher")
	inputBox := lipgloss.NewStyle().
		Border(lipgloss.NormalBorder()).
		BorderForeground(dimGreen).
		Padding(0, 1).
		Render(m.textarea.View())
	agents := m.agentLine()
	images := m.imageLine(boxWidth - 8)
	status := m.statusLine(boxWidth - 8)
	help := subtle.Width(boxWidth - 8).Align(lipgloss.Center).Render("ctrl+r launch   tab agents   arrows adjust   ctrl+c quit")

	body := lipgloss.JoinVertical(
		lipgloss.Center,
		header,
		subheader,
		"",
		inputBox,
		"",
		agents,
		images,
		status,
		help,
	)
	rendered := frame.Width(boxWidth).Render(body)
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, rendered)
}

func (m model) agentLine() string {
	items := []string{
		fmt.Sprintf("Claude %d", m.cfg.claudeCount),
		fmt.Sprintf("Codex %d", m.cfg.codexCount),
		fmt.Sprintf("OpenCode %d", m.cfg.openCount),
	}
	for i, item := range items {
		if m.focus == focusAgents && i == m.selectedAgent {
			items[i] = hot.Render("[" + item + "]")
		} else {
			items[i] = subtle.Render(item)
		}
	}
	return lipgloss.JoinHorizontal(lipgloss.Center, items[0], "  ", items[1], "  ", items[2])
}

func (m model) imageLine(width int) string {
	if len(m.images) == 0 {
		return subtle.Width(width).Align(lipgloss.Center).Render("Images: drop or paste a file")
	}
	parts := make([]string, 0, len(m.images))
	for _, image := range m.images {
		parts = append(parts, hot.Render(image.Token)+" "+subtle.Render(image.Name))
	}
	return lipgloss.NewStyle().Width(width).Align(lipgloss.Center).Render("Images: " + strings.Join(parts, "  "))
}

func (m model) statusLine(width int) string {
	text := m.status
	if m.launching {
		text = "creating worktrees and workspace..."
	}
	style := subtle
	if m.statusKind == "error" {
		style = errorText
	} else if m.statusKind == "ok" || m.launching {
		style = hot
	}
	if strings.TrimSpace(text) == "" {
		text = "ready"
	}
	return style.Width(width).Align(lipgloss.Center).Render(text)
}

func (m *model) replaceImagePaths(input string) (string, bool) {
	tokens := shellTokens(input)
	if len(tokens) == 0 {
		return input, false
	}

	type replacement struct {
		start int
		end   int
		token string
	}
	var replacements []replacement
	for _, token := range tokens {
		path, ok := normalizeImagePath(token.value)
		if !ok {
			continue
		}
		replacements = append(replacements, replacement{
			start: token.rawStart,
			end:   token.rawEnd,
			token: m.imageTokenForPath(path),
		})
	}
	if len(replacements) == 0 {
		return input, false
	}

	var out strings.Builder
	last := 0
	for _, repl := range replacements {
		if repl.start < last {
			continue
		}
		out.WriteString(input[last:repl.start])
		out.WriteString(repl.token)
		last = repl.end
	}
	out.WriteString(input[last:])
	return out.String(), true
}

func (m *model) imageTokenForPath(path string) string {
	for _, image := range m.images {
		if image.Path == path {
			return image.Token
		}
	}
	token := fmt.Sprintf("[Image #%d]", len(m.images)+1)
	m.images = append(m.images, imageAttachment{
		Token: token,
		Path:  path,
		Name:  filepath.Base(path),
	})
	return token
}

func (m *model) normalizeImageTokenCursor(direction string) {
	lines := strings.Split(m.textarea.Value(), "\n")
	lineIndex := m.textarea.Line()
	if lineIndex < 0 || lineIndex >= len(lines) {
		return
	}
	line := lines[lineIndex]
	info := m.textarea.LineInfo()
	col := info.StartColumn + info.CharOffset
	for _, loc := range imageTokenRE.FindAllStringIndex(line, -1) {
		start := runeIndexAtByte(line, loc[0])
		end := runeIndexAtByte(line, loc[1])
		if col > start && col < end {
			if direction == "left" {
				m.textarea.SetCursor(start)
			} else {
				m.textarea.SetCursor(end)
			}
			return
		}
	}
}

func shellTokens(input string) []tokenRange {
	var tokens []tokenRange
	var current strings.Builder
	inToken := false
	start := 0
	quote := rune(0)
	escaping := false

	flush := func(end int) {
		if !inToken {
			return
		}
		tokens = append(tokens, tokenRange{
			rawStart: start,
			rawEnd:   end,
			value:    current.String(),
		})
		current.Reset()
		inToken = false
		quote = 0
		escaping = false
	}

	for i, r := range input {
		if !inToken && !unicode.IsSpace(r) {
			inToken = true
			start = i
		}
		if !inToken {
			continue
		}
		if escaping {
			current.WriteRune(r)
			escaping = false
			continue
		}
		if r == '\\' {
			escaping = true
			continue
		}
		if quote != 0 {
			if r == quote {
				quote = 0
			} else {
				current.WriteRune(r)
			}
			continue
		}
		if r == '\'' || r == '"' {
			quote = r
			continue
		}
		if unicode.IsSpace(r) {
			flush(i)
			continue
		}
		current.WriteRune(r)
	}
	flush(len(input))
	return tokens
}

func normalizeImagePath(raw string) (string, bool) {
	value := strings.TrimSpace(raw)
	if value == "" {
		return "", false
	}
	if strings.HasPrefix(value, "file://") {
		parsed, err := url.Parse(value)
		if err != nil || !parsed.IsAbs() {
			return "", false
		}
		value = parsed.Path
	}
	if strings.HasPrefix(value, "~") {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", false
		}
		if value == "~" {
			value = home
		} else if strings.HasPrefix(value, "~/") {
			value = filepath.Join(home, value[2:])
		}
	}
	if !filepath.IsAbs(value) {
		abs, err := filepath.Abs(value)
		if err != nil {
			return "", false
		}
		value = abs
	}
	ext := strings.ToLower(filepath.Ext(value))
	if !imageExtensions[ext] {
		return "", false
	}
	info, err := os.Stat(value)
	if err != nil || info.IsDir() {
		return "", false
	}
	clean, err := filepath.EvalSymlinks(value)
	if err == nil {
		value = clean
	}
	return filepath.Clean(value), true
}

func runeIndexAtByte(s string, byteIndex int) int {
	if byteIndex <= 0 {
		return 0
	}
	if byteIndex >= len(s) {
		return utf8.RuneCountInString(s)
	}
	return utf8.RuneCountInString(s[:byteIndex])
}

func firstNonEmptyLine(s string) string {
	for _, line := range strings.Split(s, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			return line
		}
	}
	return ""
}

func plural(count int) string {
	if count == 1 {
		return ""
	}
	return "s"
}

func clampInt(value, minValue, maxValue int) int {
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}
