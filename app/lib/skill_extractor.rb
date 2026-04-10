# Curated skill list for test automation / QA roles.
# Each entry: canonical name => array of regex-safe match patterns (case-insensitive,
# matched with word boundaries). Order in the hash is irrelevant — ranking is by count.
#
# Keep the list tight: a skill is only useful here if it shows up in real postings AND
# tells a candidate something actionable about what to learn.
class SkillExtractor
  SKILLS = {
    "Playwright"   => ["playwright"],
    "Selenium"     => ["selenium"],
    "Cypress"      => ["cypress"],
    "Appium"       => ["appium"],
    "WebdriverIO"  => ["webdriverio", "webdriver\\.io", "wdio"],
    "Puppeteer"    => ["puppeteer"],
    "TestCafe"     => ["testcafe"],
    "Robot Framework" => ["robot framework"],
    "Cucumber"     => ["cucumber"],
    "JUnit"        => ["junit"],
    "TestNG"       => ["testng"],
    "pytest"       => ["pytest"],
    "Jest"         => ["jest"],
    "Mocha"        => ["mocha"],
    "Postman"      => ["postman"],
    "REST Assured" => ["rest assured", "rest-assured"],
    "k6"           => ["k6"],
    "JMeter"       => ["jmeter"],
    "Gatling"      => ["gatling"],
    "Python"       => ["python"],
    "JavaScript"   => ["javascript"],
    "TypeScript"   => ["typescript"],
    "Java"         => ["java"],
    "C#"           => ["c#", "\\.net"],
    "Ruby"         => ["ruby"],
    "Go"           => ["golang"],
    "SQL"          => ["sql"],
    "Git"          => ["git"],
    "CI/CD"        => ["ci/cd", "ci / cd", "continuous integration"],
    "Jenkins"      => ["jenkins"],
    "GitHub Actions" => ["github actions"],
    "Docker"       => ["docker"],
    "Kubernetes"   => ["kubernetes", "k8s"],
    "AWS"          => ["aws", "amazon web services"],
    "Azure"        => ["azure"],
    "GCP"          => ["gcp", "google cloud"],
    "Agile"        => ["agile", "scrum"],
    "API Testing"  => ["api testing", "api test"],
    "Mobile Testing" => ["mobile testing", "ios testing", "android testing"],
    "Performance Testing" => ["performance testing", "load testing"],
    "Accessibility" => ["accessibility", "a11y", "wcag"],
    "Claude"       => ["claude code", "claude\\b"],
    "Cursor"       => ["cursor\\b"],
    "Copilot"      => ["copilot"],
    "LLM"          => ["llm", "large language model"],
    "Machine Learning" => ["machine learning", "\\bml\\b"],
    "LangChain"    => ["langchain", "langgraph"],
    "CrewAI"       => ["crewai", "crew ai"],
    "AutoGen"      => ["autogen"],
    "OpenAI API"   => ["openai", "gpt-4", "gpt-3", "chatgpt"],
    "Anthropic"    => ["anthropic"],
    "RAG"          => ["\\brag\\b", "retrieval.augmented"],
    "Vector DB"    => ["pinecone", "weaviate", "chromadb", "chroma", "vector database", "vector db", "pgvector", "qdrant"],
    "Prompt Engineering" => ["prompt engineering", "prompt design"],
    "Multi-Agent"  => ["multi.agent", "multi agent", "agentic"],
    "Function Calling" => ["function calling", "tool use", "tool calling"],
    "MCP"          => ["model context protocol", "\\bmcp\\b"],
    "Agent SDK"    => ["agent sdk", "agents sdk"],
    "Hugging Face" => ["hugging face", "huggingface", "transformers"],
    "PyTorch"      => ["pytorch"],
    "TensorFlow"   => ["tensorflow"]
  }.freeze

  # Compile patterns once at load.
  PATTERNS = SKILLS.transform_values do |variants|
    Regexp.new("\\b(?:#{variants.join('|')})\\b", Regexp::IGNORECASE)
  end.freeze

  # Returns array of [skill_name, count, percent] sorted by count desc.
  # `jobs` should be an ActiveRecord relation already filtered to whatever set
  # you want stats for (e.g. Job.active).
  def self.top_skills(jobs, limit: 10)
    rows = jobs.where.not(description: [nil, ""]).pluck(:title, :description)
    return [] if rows.empty?

    counts = Hash.new(0)
    rows.each do |title, description|
      blob = "#{title} #{description}"
      PATTERNS.each do |skill, pattern|
        counts[skill] += 1 if blob.match?(pattern)
      end
    end

    total = rows.length
    counts.sort_by { |_, c| -c }.first(limit).map do |name, count|
      [name, count, (count.to_f / total * 100).round]
    end
  end

  def self.canonical_names
    SKILLS.keys
  end
end
