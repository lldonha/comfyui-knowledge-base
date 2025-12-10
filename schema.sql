-- ============================================================================
-- COMFYUI KNOWLEDGE BASE - PostgreSQL Schema
-- Sistema ético de coleta e análise de conteúdo ComfyUI
-- Database: cosmic (existente)
-- ============================================================================

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";  -- pgvector para embeddings

-- ============================================================================
-- CONFIGURAÇÃO E RATE LIMITING
-- ============================================================================

-- Tabela de configuração de APIs
CREATE TABLE IF NOT EXISTS api_configs (
    id SERIAL PRIMARY KEY,
    api_name VARCHAR(50) UNIQUE NOT NULL,  -- 'gemini', 'youtube', 'github'
    
    -- Rate limits
    requests_per_minute INT DEFAULT 15,
    requests_per_hour INT DEFAULT 1000,
    requests_per_day INT DEFAULT 1500,
    
    -- Tracking
    current_minute_count INT DEFAULT 0,
    current_hour_count INT DEFAULT 0,
    current_day_count INT DEFAULT 0,
    
    minute_reset_at TIMESTAMP,
    hour_reset_at TIMESTAMP,
    day_reset_at TIMESTAMP,
    
    -- API Key (criptografada ou referência)
    api_key_env_var VARCHAR(100),  -- Nome da variável de ambiente
    
    is_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Configurações padrão
INSERT INTO api_configs (api_name, requests_per_minute, requests_per_hour, requests_per_day, api_key_env_var) VALUES
    ('gemini_flash', 15, 1000, 1500, 'GEMINI_API_KEY'),
    ('gemini_pro', 2, 50, 50, 'GEMINI_API_KEY'),
    ('youtube_data', 100, 1000, 10000, 'YOUTUBE_API_KEY'),
    ('github', 60, 5000, 5000, 'GITHUB_TOKEN')
ON CONFLICT (api_name) DO NOTHING;

-- ============================================================================
-- FONTES E CRIADORES
-- ============================================================================

-- Plataformas suportadas
CREATE TYPE platform_type AS ENUM (
    'youtube',
    'github', 
    'openart',
    'civitai',
    'comfyworkflows',
    'runninghub',
    'huggingface',
    'discord',
    'other'
);

-- Status de monitoramento
CREATE TYPE monitoring_status AS ENUM (
    'active',      -- Monitorando ativamente
    'paused',      -- Pausado temporariamente
    'archived',    -- Não monitora mais, mas mantém dados
    'pending'      -- Aguardando primeira sincronização
);

-- Criadores/Canais
CREATE TABLE IF NOT EXISTS creators (
    id SERIAL PRIMARY KEY,
    
    -- Identificação
    name VARCHAR(255) NOT NULL,
    handle VARCHAR(255),  -- @pixaroma, username, etc
    
    -- Descrição (pode ser preenchida pelo Gemini)
    bio TEXT,
    specialties TEXT[],  -- ['flux', 'video', 'upscaling']
    
    -- Links
    website_url TEXT,
    discord_url TEXT,
    patreon_url TEXT,
    
    -- Métricas agregadas
    total_videos INT DEFAULT 0,
    total_workflows INT DEFAULT 0,
    quality_score DECIMAL(3,2),  -- 0.00 a 5.00
    
    -- Controle
    is_verified BOOLEAN DEFAULT false,  -- Verificado manualmente
    notes TEXT,
    
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Fontes (cada plataforma de um criador)
CREATE TABLE IF NOT EXISTS sources (
    id SERIAL PRIMARY KEY,
    creator_id INT REFERENCES creators(id) ON DELETE CASCADE,
    
    -- Identificação da fonte
    platform platform_type NOT NULL,
    platform_id VARCHAR(255),  -- YouTube channel ID, GitHub username, etc
    platform_url TEXT NOT NULL,
    
    -- Configuração de monitoramento
    monitoring_status monitoring_status DEFAULT 'pending',
    check_frequency_hours INT DEFAULT 12,  -- Verificar a cada X horas
    
    -- Última sincronização
    last_checked_at TIMESTAMP,
    last_new_content_at TIMESTAMP,
    next_check_at TIMESTAMP,
    
    -- Estatísticas
    total_items_found INT DEFAULT 0,
    total_items_processed INT DEFAULT 0,
    error_count INT DEFAULT 0,
    last_error TEXT,
    
    -- Metadados específicos da plataforma (JSON flexível)
    platform_metadata JSONB DEFAULT '{}',
    
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(platform, platform_id)
);

-- ============================================================================
-- FILA DE PROCESSAMENTO
-- ============================================================================

CREATE TYPE job_status AS ENUM (
    'pending',
    'processing',
    'completed',
    'failed',
    'cancelled'
);

CREATE TYPE job_type AS ENUM (
    'discover_source',      -- Descobrir e cadastrar nova fonte
    'sync_source',          -- Sincronizar fonte (buscar novos itens)
    'analyze_video',        -- Análise completa de vídeo com Gemini
    'extract_frames',       -- Extrair frames de timestamps
    'download_workflow',    -- Baixar workflow JSON
    'generate_embeddings',  -- Gerar embeddings para busca
    'analyze_workflow'      -- Analisar nodes de um workflow
);

CREATE TABLE IF NOT EXISTS job_queue (
    id SERIAL PRIMARY KEY,
    
    -- Tipo e prioridade
    job_type job_type NOT NULL,
    priority INT DEFAULT 5,  -- 1 (baixa) a 10 (alta)
    
    -- Referências (opcional, depende do tipo)
    source_id INT REFERENCES sources(id) ON DELETE CASCADE,
    video_id INT,  -- FK adicionada depois
    workflow_id INT,  -- FK adicionada depois
    
    -- Dados do job (flexível)
    input_data JSONB DEFAULT '{}',
    output_data JSONB DEFAULT '{}',
    
    -- Status
    status job_status DEFAULT 'pending',
    attempts INT DEFAULT 0,
    max_attempts INT DEFAULT 3,
    
    -- Timing
    created_at TIMESTAMP DEFAULT NOW(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    scheduled_for TIMESTAMP DEFAULT NOW(),  -- Permite agendamento
    
    -- Erro (se houver)
    error_message TEXT,
    error_details JSONB,
    
    -- Rate limiting
    api_used VARCHAR(50),  -- Qual API este job usa
    tokens_consumed INT DEFAULT 0
);

-- Índices para performance da fila
CREATE INDEX idx_job_queue_status_priority ON job_queue(status, priority DESC, scheduled_for);
CREATE INDEX idx_job_queue_source ON job_queue(source_id) WHERE source_id IS NOT NULL;

-- ============================================================================
-- VÍDEOS E CONTEÚDO
-- ============================================================================

CREATE TABLE IF NOT EXISTS videos (
    id SERIAL PRIMARY KEY,
    source_id INT REFERENCES sources(id) ON DELETE CASCADE,
    
    -- Identificação
    external_id VARCHAR(255) NOT NULL,  -- YouTube video ID
    url TEXT NOT NULL,
    
    -- Metadados básicos
    title TEXT NOT NULL,
    description TEXT,
    thumbnail_url TEXT,
    
    -- Duração e datas
    duration_seconds INT,
    published_at TIMESTAMP,
    
    -- Métricas (opcionais, da API)
    view_count BIGINT,
    like_count INT,
    comment_count INT,
    
    -- Links extraídos da descrição
    extracted_links JSONB DEFAULT '[]',
    
    -- Status de processamento
    transcript_status VARCHAR(20) DEFAULT 'pending',  -- pending, processing, completed, failed, unavailable
    analysis_status VARCHAR(20) DEFAULT 'pending',
    frames_status VARCHAR(20) DEFAULT 'pending',
    
    -- Caminho do vídeo baixado (se aplicável)
    local_video_path TEXT,
    
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(source_id, external_id)
);

-- Adicionar FK na job_queue
ALTER TABLE job_queue ADD CONSTRAINT fk_job_video 
    FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE;

-- ============================================================================
-- TRANSCRIÇÕES
-- ============================================================================

CREATE TABLE IF NOT EXISTS transcripts (
    id SERIAL PRIMARY KEY,
    video_id INT REFERENCES videos(id) ON DELETE CASCADE UNIQUE,
    
    -- Conteúdo
    full_text TEXT,
    language VARCHAR(10) DEFAULT 'en',
    is_auto_generated BOOLEAN DEFAULT true,
    
    -- Segmentos com timestamps (para busca precisa)
    segments JSONB DEFAULT '[]',  -- [{start: 0, end: 5, text: "..."}]
    
    -- Métricas
    word_count INT,
    duration_covered_seconds INT,
    
    created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- ANÁLISE DO GEMINI
-- ============================================================================

CREATE TABLE IF NOT EXISTS video_analysis (
    id SERIAL PRIMARY KEY,
    video_id INT REFERENCES videos(id) ON DELETE CASCADE UNIQUE,
    
    -- Resumo
    summary TEXT,
    summary_pt TEXT,  -- Versão em português
    
    -- Classificação
    difficulty_level VARCHAR(20),  -- beginner, intermediate, advanced
    estimated_duration_minutes INT,
    
    -- Conteúdo identificado
    key_topics TEXT[],
    techniques_shown TEXT[],
    models_mentioned TEXT[],
    custom_nodes_mentioned TEXT[],
    
    -- Links e recursos mencionados
    workflow_links TEXT[],
    resource_links JSONB DEFAULT '[]',
    
    -- Pré-requisitos
    prerequisites TEXT[],
    
    -- Resposta completa do Gemini (para debug/reprocessamento)
    raw_response JSONB,
    
    -- Metadados
    model_used VARCHAR(50),  -- gemini-1.5-flash, etc
    tokens_used INT,
    analysis_version INT DEFAULT 1,
    
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- MOMENTOS-CHAVE E FRAMES
-- ============================================================================

CREATE TYPE moment_type AS ENUM (
    'intro',
    'workflow_shown',
    'node_explained',
    'settings_shown',
    'tip',
    'result',
    'comparison',
    'outro',
    'other'
);

CREATE TABLE IF NOT EXISTS video_moments (
    id SERIAL PRIMARY KEY,
    video_id INT REFERENCES videos(id) ON DELETE CASCADE,
    
    -- Timestamp
    timestamp_seconds INT NOT NULL,
    timestamp_formatted VARCHAR(20),  -- "05:32"
    duration_seconds INT DEFAULT 5,  -- Duração do momento
    
    -- Classificação
    moment_type moment_type DEFAULT 'other',
    importance_score INT CHECK (importance_score BETWEEN 1 AND 10),
    
    -- Descrição
    description TEXT,
    description_pt TEXT,
    
    -- Conteúdo identificado
    nodes_visible TEXT[],
    settings_visible JSONB,
    
    -- Frame extraído
    frame_path TEXT,  -- Caminho local do frame
    frame_thumbnail_path TEXT,  -- Versão menor para preview
    
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_moments_video_timestamp ON video_moments(video_id, timestamp_seconds);

-- ============================================================================
-- WORKFLOWS
-- ============================================================================

CREATE TYPE workflow_source_type AS ENUM (
    'video_description',  -- Extraído de descrição de vídeo
    'video_content',      -- Mostrado no vídeo
    'github_repo',
    'openart',
    'civitai',
    'comfyworkflows',
    'direct_upload',
    'other'
);

CREATE TABLE IF NOT EXISTS workflows (
    id SERIAL PRIMARY KEY,
    
    -- Origem
    source_type workflow_source_type NOT NULL,
    source_url TEXT,
    source_video_id INT REFERENCES videos(id) ON DELETE SET NULL,
    creator_id INT REFERENCES creators(id) ON DELETE SET NULL,
    
    -- Identificação
    name VARCHAR(255),
    description TEXT,
    version VARCHAR(50),
    
    -- Conteúdo
    workflow_json JSONB,
    file_path TEXT,  -- Caminho local se salvo
    file_hash VARCHAR(64),  -- SHA256 para detectar duplicatas
    
    -- Análise de nodes
    total_nodes INT,
    primitive_nodes TEXT[],
    custom_nodes TEXT[],
    node_counts JSONB,  -- {"KSampler": 2, "VAEDecode": 1}
    
    -- Classificação
    complexity_score INT,  -- Baseado em quantidade/tipos de nodes
    categories TEXT[],  -- ['txt2img', 'upscaling', 'video']
    tags TEXT[],
    
    -- Compatibilidade
    min_comfyui_version VARCHAR(20),
    required_models TEXT[],
    required_custom_nodes TEXT[],
    
    -- Métricas (se disponível da fonte)
    download_count INT,
    like_count INT,
    
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Adicionar FK na job_queue
ALTER TABLE job_queue ADD CONSTRAINT fk_job_workflow 
    FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE;

-- Índice para detectar duplicatas
CREATE INDEX idx_workflow_hash ON workflows(file_hash) WHERE file_hash IS NOT NULL;

-- ============================================================================
-- CATÁLOGO DE NODES
-- ============================================================================

CREATE TABLE IF NOT EXISTS nodes_catalog (
    id SERIAL PRIMARY KEY,
    
    -- Identificação
    node_name VARCHAR(255) UNIQUE NOT NULL,
    node_type VARCHAR(50),  -- 'primitive', 'custom'
    
    -- Origem (para custom nodes)
    package_name VARCHAR(255),  -- ComfyUI-Impact-Pack
    package_url TEXT,
    
    -- Descrição
    description TEXT,
    category VARCHAR(100),
    
    -- Estatísticas de uso
    usage_count INT DEFAULT 0,
    workflow_count INT DEFAULT 0,
    
    -- Metadados
    inputs JSONB,
    outputs JSONB,
    
    first_seen_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Relação N:N entre workflows e nodes
CREATE TABLE IF NOT EXISTS workflow_nodes (
    workflow_id INT REFERENCES workflows(id) ON DELETE CASCADE,
    node_id INT REFERENCES nodes_catalog(id) ON DELETE CASCADE,
    count INT DEFAULT 1,
    PRIMARY KEY (workflow_id, node_id)
);

-- ============================================================================
-- EMBEDDINGS PARA BUSCA SEMÂNTICA
-- ============================================================================

CREATE TABLE IF NOT EXISTS embeddings (
    id SERIAL PRIMARY KEY,
    
    -- Referência (uma dessas será preenchida)
    video_id INT REFERENCES videos(id) ON DELETE CASCADE,
    workflow_id INT REFERENCES workflows(id) ON DELETE CASCADE,
    transcript_id INT REFERENCES transcripts(id) ON DELETE CASCADE,
    
    -- Tipo de conteúdo
    content_type VARCHAR(50),  -- 'title', 'summary', 'transcript_chunk', 'workflow_description'
    content_text TEXT,  -- Texto original que gerou o embedding
    
    -- Embedding
    embedding vector(1536),  -- Dimensão para text-embedding-3-small ou similar
    
    -- Metadados
    model_used VARCHAR(100),
    chunk_index INT,  -- Se for parte de um texto maior
    
    created_at TIMESTAMP DEFAULT NOW(),
    
    -- Apenas uma referência por registro
    CONSTRAINT single_reference CHECK (
        (video_id IS NOT NULL)::int +
        (workflow_id IS NOT NULL)::int +
        (transcript_id IS NOT NULL)::int = 1
    )
);

-- Índice para busca por similaridade
CREATE INDEX idx_embeddings_vector ON embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ============================================================================
-- LOGS E AUDITORIA
-- ============================================================================

CREATE TABLE IF NOT EXISTS activity_log (
    id SERIAL PRIMARY KEY,
    
    -- Ação
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),  -- 'video', 'workflow', 'source'
    entity_id INT,
    
    -- Detalhes
    details JSONB,
    
    -- API usage
    api_used VARCHAR(50),
    tokens_consumed INT,
    cost_usd DECIMAL(10, 6),
    
    created_at TIMESTAMP DEFAULT NOW()
);

-- Limpar logs antigos (manter 30 dias)
CREATE INDEX idx_activity_log_created ON activity_log(created_at);

-- ============================================================================
-- VIEWS ÚTEIS
-- ============================================================================

-- View de fontes para monitoramento
CREATE OR REPLACE VIEW v_sources_to_check AS
SELECT 
    s.*,
    c.name as creator_name,
    c.handle as creator_handle
FROM sources s
JOIN creators c ON s.creator_id = c.id
WHERE s.monitoring_status = 'active'
  AND (s.next_check_at IS NULL OR s.next_check_at <= NOW())
ORDER BY s.next_check_at ASC NULLS FIRST;

-- View de jobs pendentes com prioridade
CREATE OR REPLACE VIEW v_pending_jobs AS
SELECT 
    jq.*,
    ac.requests_per_minute,
    ac.current_minute_count
FROM job_queue jq
LEFT JOIN api_configs ac ON jq.api_used = ac.api_name
WHERE jq.status = 'pending'
  AND jq.scheduled_for <= NOW()
  AND (ac.is_enabled IS NULL OR ac.is_enabled = true)
ORDER BY jq.priority DESC, jq.created_at ASC;

-- View de estatísticas por criador
CREATE OR REPLACE VIEW v_creator_stats AS
SELECT 
    c.id,
    c.name,
    c.handle,
    COUNT(DISTINCT s.id) as source_count,
    COUNT(DISTINCT v.id) as video_count,
    COUNT(DISTINCT w.id) as workflow_count,
    MAX(v.published_at) as latest_video_at
FROM creators c
LEFT JOIN sources s ON c.id = s.creator_id
LEFT JOIN videos v ON s.id = v.source_id
LEFT JOIN workflows w ON c.id = w.creator_id
GROUP BY c.id;

-- ============================================================================
-- FUNÇÕES AUXILIARES
-- ============================================================================

-- Função para verificar rate limit e incrementar contador
CREATE OR REPLACE FUNCTION check_and_increment_rate_limit(p_api_name VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    v_config api_configs%ROWTYPE;
    v_now TIMESTAMP := NOW();
BEGIN
    SELECT * INTO v_config FROM api_configs WHERE api_name = p_api_name FOR UPDATE;
    
    IF NOT FOUND OR NOT v_config.is_enabled THEN
        RETURN FALSE;
    END IF;
    
    -- Reset contadores se necessário
    IF v_config.minute_reset_at IS NULL OR v_config.minute_reset_at <= v_now THEN
        v_config.current_minute_count := 0;
        v_config.minute_reset_at := v_now + INTERVAL '1 minute';
    END IF;
    
    IF v_config.hour_reset_at IS NULL OR v_config.hour_reset_at <= v_now THEN
        v_config.current_hour_count := 0;
        v_config.hour_reset_at := v_now + INTERVAL '1 hour';
    END IF;
    
    IF v_config.day_reset_at IS NULL OR v_config.day_reset_at <= v_now THEN
        v_config.current_day_count := 0;
        v_config.day_reset_at := v_now + INTERVAL '1 day';
    END IF;
    
    -- Verificar se está dentro dos limites
    IF v_config.current_minute_count >= v_config.requests_per_minute OR
       v_config.current_hour_count >= v_config.requests_per_hour OR
       v_config.current_day_count >= v_config.requests_per_day THEN
        RETURN FALSE;
    END IF;
    
    -- Incrementar contadores
    UPDATE api_configs SET
        current_minute_count = v_config.current_minute_count + 1,
        current_hour_count = v_config.current_hour_count + 1,
        current_day_count = v_config.current_day_count + 1,
        minute_reset_at = v_config.minute_reset_at,
        hour_reset_at = v_config.hour_reset_at,
        day_reset_at = v_config.day_reset_at,
        updated_at = v_now
    WHERE api_name = p_api_name;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Função para adicionar job à fila
CREATE OR REPLACE FUNCTION enqueue_job(
    p_job_type job_type,
    p_priority INT DEFAULT 5,
    p_source_id INT DEFAULT NULL,
    p_video_id INT DEFAULT NULL,
    p_workflow_id INT DEFAULT NULL,
    p_input_data JSONB DEFAULT '{}',
    p_api_used VARCHAR DEFAULT NULL,
    p_scheduled_for TIMESTAMP DEFAULT NOW()
)
RETURNS INT AS $$
DECLARE
    v_job_id INT;
BEGIN
    INSERT INTO job_queue (
        job_type, priority, source_id, video_id, workflow_id,
        input_data, api_used, scheduled_for
    ) VALUES (
        p_job_type, p_priority, p_source_id, p_video_id, p_workflow_id,
        p_input_data, p_api_used, p_scheduled_for
    )
    RETURNING id INTO v_job_id;
    
    RETURN v_job_id;
END;
$$ LANGUAGE plpgsql;

-- Função para busca semântica
CREATE OR REPLACE FUNCTION search_similar(
    p_query_embedding vector(1536),
    p_limit INT DEFAULT 10,
    p_content_type VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id INT,
    content_type VARCHAR,
    content_text TEXT,
    video_id INT,
    workflow_id INT,
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.id,
        e.content_type,
        e.content_text,
        e.video_id,
        e.workflow_id,
        1 - (e.embedding <=> p_query_embedding) as similarity
    FROM embeddings e
    WHERE (p_content_type IS NULL OR e.content_type = p_content_type)
    ORDER BY e.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_creators_updated_at BEFORE UPDATE ON creators
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_sources_updated_at BEFORE UPDATE ON sources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_videos_updated_at BEFORE UPDATE ON videos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_video_analysis_updated_at BEFORE UPDATE ON video_analysis
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_workflows_updated_at BEFORE UPDATE ON workflows
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- DADOS INICIAIS - Pixaroma como exemplo
-- ============================================================================

INSERT INTO creators (name, handle, website_url, discord_url, specialties, notes)
VALUES (
    'Pixaroma',
    'pixaroma',
    'https://pixaroma.com',
    'https://discord.gg/pixaroma',
    ARRAY['comfyui', 'flux', 'sdxl', 'tutorials', 'workflows'],
    'Excelentes tutoriais de ComfyUI, workflows bem organizados'
) ON CONFLICT DO NOTHING;

INSERT INTO sources (creator_id, platform, platform_id, platform_url, monitoring_status, check_frequency_hours)
SELECT 
    c.id,
    'youtube'::platform_type,
    'UCxxxxxxxxx',  -- Substituir pelo ID real do canal
    'https://www.youtube.com/@pixaroma',
    'pending'::monitoring_status,
    12
FROM creators c WHERE c.handle = 'pixaroma'
ON CONFLICT DO NOTHING;

-- ============================================================================
-- COMENTÁRIOS DE DOCUMENTAÇÃO
-- ============================================================================

COMMENT ON TABLE creators IS 'Criadores de conteúdo de ComfyUI que são monitorados';
COMMENT ON TABLE sources IS 'Fontes específicas de cada criador (YouTube, GitHub, etc)';
COMMENT ON TABLE job_queue IS 'Fila de processamento com rate limiting';
COMMENT ON TABLE videos IS 'Vídeos descobertos e processados';
COMMENT ON TABLE video_analysis IS 'Análise feita pelo Gemini de cada vídeo';
COMMENT ON TABLE video_moments IS 'Momentos-chave com timestamps e frames';
COMMENT ON TABLE workflows IS 'Workflows extraídos de várias fontes';
COMMENT ON TABLE nodes_catalog IS 'Catálogo de todos os nodes encontrados';
COMMENT ON TABLE embeddings IS 'Embeddings para busca semântica';

COMMENT ON FUNCTION check_and_increment_rate_limit IS 'Verifica e incrementa rate limit atomicamente';
COMMENT ON FUNCTION enqueue_job IS 'Adiciona job à fila de processamento';
COMMENT ON FUNCTION search_similar IS 'Busca semântica por similaridade de embeddings';
