#!/usr/bin/env python3
"""
ComfyUI Knowledge Base - Video Analyzer
Analisa vídeos do YouTube usando Gemini 1.5 Flash com upload direto do vídeo.
"""

import os
import sys
import json
import time
import hashlib
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any

import psycopg2
from psycopg2.extras import RealDictCursor
import google.generativeai as genai

# Configuração
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "host.docker.internal"),
    "port": os.getenv("DB_PORT", "5432"),
    "database": os.getenv("DB_NAME", "cosmic"),
    "user": os.getenv("DB_USER", "lucas"),
    "password": os.getenv("DB_PASSWORD", "")
}

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
DATA_DIR = Path(os.getenv("DATA_DIR", "/data/comfyui_kb"))
FRAMES_DIR = DATA_DIR / "frames"
VIDEOS_DIR = DATA_DIR / "videos"

# Criar diretórios
FRAMES_DIR.mkdir(parents=True, exist_ok=True)
VIDEOS_DIR.mkdir(parents=True, exist_ok=True)

# Prompt para análise de vídeo
VIDEO_ANALYSIS_PROMPT = """
Analise este tutorial de ComfyUI em detalhes. Assista o vídeo completo e extraia informações estruturadas.

IMPORTANTE: Identifique os momentos exatos (timestamps) onde:
1. O workflow completo aparece na tela
2. Nodes específicos são explicados ou configurados
3. Dicas importantes são mencionadas
4. Resultados/outputs são mostrados
5. Configurações importantes são alteradas

Retorne APENAS um JSON válido (sem markdown, sem ```), com esta estrutura:

{
  "summary": "Resumo detalhado em 3-4 parágrafos do que o vídeo ensina, incluindo o contexto e objetivos",
  "summary_pt": "Mesmo resumo em português brasileiro",
  
  "key_topics": ["lista", "de", "tópicos", "principais"],
  
  "techniques": ["técnicas mostradas como img2img, controlnet, upscaling, inpainting, etc"],
  
  "models_mentioned": ["SDXL", "Flux", "SD 1.5", "ou outros modelos mencionados"],
  
  "custom_nodes_mentioned": ["ComfyUI-Manager", "Impact Pack", "ou outros custom nodes"],
  
  "difficulty": "beginner|intermediate|advanced",
  
  "prerequisites": ["conhecimentos necessários antes de assistir"],
  
  "workflow_type": "txt2img|img2img|video|upscaling|inpainting|controlnet|other",
  
  "key_moments": [
    {
      "timestamp_seconds": 0,
      "timestamp_formatted": "00:00",
      "type": "intro|workflow_shown|node_explained|settings_shown|tip|result|comparison|outro",
      "description": "Descrição detalhada do que está acontecendo neste momento",
      "description_pt": "Mesma descrição em português",
      "nodes_visible": ["lista de nodes visíveis na tela se aplicável"],
      "importance": 8
    }
  ],
  
  "workflow_links_mentioned": ["URLs de workflows mencionados no vídeo"],
  
  "chapter_summary": [
    {
      "start_seconds": 0,
      "end_seconds": 60,
      "title": "Título do capítulo",
      "summary": "O que é coberto neste trecho"
    }
  ],
  
  "practical_tips": ["dicas práticas extraídas do vídeo"],
  
  "common_mistakes_mentioned": ["erros comuns que o criador menciona evitar"],
  
  "settings_recommendations": {
    "sampler": "recomendação de sampler se mencionado",
    "steps": "número de steps recomendado",
    "cfg_scale": "CFG scale recomendado",
    "other": "outras configurações importantes"
  }
}

Seja muito preciso com os timestamps - eles serão usados para extrair frames.
Foque especialmente em momentos onde a UI do ComfyUI está visível.
"""


class DatabaseConnection:
    """Gerencia conexão com PostgreSQL."""
    
    def __init__(self):
        self.conn = None
        
    def __enter__(self):
        self.conn = psycopg2.connect(**DB_CONFIG)
        return self.conn
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.conn:
            if exc_type:
                self.conn.rollback()
            else:
                self.conn.commit()
            self.conn.close()


def check_rate_limit(api_name: str = "gemini_flash") -> bool:
    """Verifica se podemos fazer uma requisição respeitando rate limits."""
    with DatabaseConnection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT check_and_increment_rate_limit(%s) as can_proceed",
                (api_name,)
            )
            result = cur.fetchone()
            return result[0] if result else False


def wait_for_rate_limit(api_name: str = "gemini_flash", max_wait: int = 120):
    """Aguarda até que o rate limit permita uma requisição."""
    waited = 0
    while not check_rate_limit(api_name):
        if waited >= max_wait:
            raise Exception(f"Rate limit não liberou após {max_wait}s")
        print(f"Rate limit atingido, aguardando... ({waited}s)")
        time.sleep(10)
        waited += 10
    print("Rate limit OK, prosseguindo...")


def download_video(video_url: str, output_path: Path, max_height: int = 720) -> bool:
    """Baixa vídeo do YouTube usando yt-dlp."""
    print(f"Baixando vídeo: {video_url}")
    
    cmd = [
        "yt-dlp",
        "-f", f"best[height<={max_height}]",
        "-o", str(output_path),
        "--no-playlist",
        "--no-warnings",
        video_url
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if result.returncode != 0:
            print(f"Erro no yt-dlp: {result.stderr}")
            return False
        return output_path.exists()
    except subprocess.TimeoutExpired:
        print("Timeout ao baixar vídeo")
        return False
    except Exception as e:
        print(f"Erro ao baixar vídeo: {e}")
        return False


def extract_frame(video_path: Path, timestamp_seconds: int, output_path: Path) -> bool:
    """Extrai um frame específico do vídeo usando FFmpeg."""
    cmd = [
        "ffmpeg",
        "-ss", str(timestamp_seconds),
        "-i", str(video_path),
        "-vframes", "1",
        "-q:v", "2",
        str(output_path),
        "-y"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return output_path.exists()
    except Exception as e:
        print(f"Erro ao extrair frame: {e}")
        return False


def extract_frames_batch(video_path: Path, timestamps: List[int], output_dir: Path) -> Dict[int, Path]:
    """Extrai múltiplos frames de uma vez."""
    output_dir.mkdir(parents=True, exist_ok=True)
    results = {}
    
    for ts in timestamps:
        frame_path = output_dir / f"frame_{ts:05d}s.jpg"
        if extract_frame(video_path, ts, frame_path):
            results[ts] = frame_path
            print(f"  ✓ Frame extraído: {ts}s")
        else:
            print(f"  ✗ Falha ao extrair frame: {ts}s")
    
    return results


def analyze_video_with_gemini(video_path: Path, title: str = "", description: str = "") -> Dict[str, Any]:
    """Analisa vídeo usando Gemini 1.5 Flash com upload direto."""
    
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY não configurada")
    
    genai.configure(api_key=GEMINI_API_KEY)
    
    # Upload do vídeo
    print(f"Fazendo upload do vídeo para Gemini...")
    video_file = genai.upload_file(path=str(video_path))
    
    # Aguardar processamento
    print("Aguardando processamento do vídeo...")
    while video_file.state.name == "PROCESSING":
        time.sleep(5)
        video_file = genai.get_file(video_file.name)
    
    if video_file.state.name != "ACTIVE":
        raise Exception(f"Falha no processamento do vídeo: {video_file.state.name}")
    
    print("Vídeo processado, iniciando análise...")
    
    # Criar prompt com contexto
    context = f"""
Título do vídeo: {title}

Descrição:
{description[:3000] if description else 'Não disponível'}

---

{VIDEO_ANALYSIS_PROMPT}
"""
    
    # Chamar Gemini
    model = genai.GenerativeModel("gemini-1.5-flash")
    
    response = model.generate_content(
        [video_file, context],
        generation_config={
            "temperature": 0.2,
            "max_output_tokens": 8192,
        }
    )
    
    # Limpar arquivo do servidor
    try:
        genai.delete_file(video_file.name)
    except:
        pass
    
    # Parsear resposta
    text = response.text
    
    # Limpar possíveis marcadores de código
    text = text.replace("```json", "").replace("```", "").strip()
    
    try:
        analysis = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"Erro ao parsear JSON: {e}")
        print(f"Resposta raw: {text[:500]}...")
        analysis = {
            "summary": text[:1000],
            "error": str(e),
            "raw_response": text
        }
    
    # Adicionar metadados
    analysis["_metadata"] = {
        "model": "gemini-1.5-flash",
        "analyzed_at": datetime.now().isoformat(),
        "tokens_used": response.usage_metadata.total_token_count if hasattr(response, 'usage_metadata') else 0
    }
    
    return analysis


def save_analysis_to_db(video_id: int, analysis: Dict[str, Any]):
    """Salva análise no banco de dados."""
    
    with DatabaseConnection() as conn:
        with conn.cursor() as cur:
            # Inserir análise principal
            cur.execute("""
                INSERT INTO video_analysis (
                    video_id,
                    summary,
                    summary_pt,
                    difficulty_level,
                    key_topics,
                    techniques_shown,
                    models_mentioned,
                    custom_nodes_mentioned,
                    prerequisites,
                    raw_response,
                    model_used,
                    tokens_used
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (video_id) DO UPDATE SET
                    summary = EXCLUDED.summary,
                    summary_pt = EXCLUDED.summary_pt,
                    difficulty_level = EXCLUDED.difficulty_level,
                    key_topics = EXCLUDED.key_topics,
                    techniques_shown = EXCLUDED.techniques_shown,
                    raw_response = EXCLUDED.raw_response,
                    updated_at = NOW()
                RETURNING id
            """, (
                video_id,
                analysis.get("summary", ""),
                analysis.get("summary_pt", ""),
                analysis.get("difficulty", "intermediate"),
                analysis.get("key_topics", []),
                analysis.get("techniques", []),
                analysis.get("models_mentioned", []),
                analysis.get("custom_nodes_mentioned", []),
                analysis.get("prerequisites", []),
                json.dumps(analysis),
                analysis.get("_metadata", {}).get("model", "gemini-1.5-flash"),
                analysis.get("_metadata", {}).get("tokens_used", 0)
            ))
            
            analysis_id = cur.fetchone()[0]
            
            # Inserir momentos-chave
            for moment in analysis.get("key_moments", []):
                cur.execute("""
                    INSERT INTO video_moments (
                        video_id,
                        timestamp_seconds,
                        timestamp_formatted,
                        moment_type,
                        description,
                        nodes_visible,
                        importance_score
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT DO NOTHING
                """, (
                    video_id,
                    moment.get("timestamp_seconds", 0),
                    moment.get("timestamp_formatted", "00:00"),
                    moment.get("type", "other"),
                    moment.get("description", ""),
                    moment.get("nodes_visible", []),
                    moment.get("importance", 5)
                ))
            
            # Atualizar status do vídeo
            cur.execute("""
                UPDATE videos SET 
                    analysis_status = 'completed',
                    updated_at = NOW()
                WHERE id = %s
            """, (video_id,))
            
            print(f"Análise salva: analysis_id={analysis_id}, {len(analysis.get('key_moments', []))} momentos")
            
            return analysis_id


def process_video(video_id: int = None, video_url: str = None, skip_download: bool = False):
    """Processa um vídeo completo: download, análise e extração de frames."""
    
    # Buscar dados do vídeo
    with DatabaseConnection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if video_id:
                cur.execute("""
                    SELECT v.*, s.platform, c.name as creator_name
                    FROM videos v
                    JOIN sources s ON v.source_id = s.id
                    JOIN creators c ON s.creator_id = c.id
                    WHERE v.id = %s
                """, (video_id,))
            elif video_url:
                # Extrair video ID do URL
                import re
                match = re.search(r'(?:v=|youtu\.be/)([a-zA-Z0-9_-]{11})', video_url)
                if not match:
                    raise ValueError(f"URL inválida: {video_url}")
                external_id = match.group(1)
                
                cur.execute("""
                    SELECT v.*, s.platform, c.name as creator_name
                    FROM videos v
                    JOIN sources s ON v.source_id = s.id
                    JOIN creators c ON s.creator_id = c.id
                    WHERE v.external_id = %s
                """, (external_id,))
            else:
                raise ValueError("video_id ou video_url é obrigatório")
            
            video = cur.fetchone()
            
            if not video:
                raise ValueError(f"Vídeo não encontrado")
    
    print(f"\n{'='*60}")
    print(f"Processando: {video['title']}")
    print(f"Criador: {video['creator_name']}")
    print(f"{'='*60}\n")
    
    video_dir = VIDEOS_DIR / str(video['id'])
    video_dir.mkdir(parents=True, exist_ok=True)
    video_path = video_dir / "video.mp4"
    
    # 1. Download do vídeo
    if not skip_download or not video_path.exists():
        wait_for_rate_limit("youtube_data")
        if not download_video(video['url'], video_path):
            raise Exception("Falha ao baixar vídeo")
    else:
        print("Usando vídeo já baixado")
    
    # 2. Análise com Gemini
    print("\nIniciando análise com Gemini...")
    wait_for_rate_limit("gemini_flash")
    
    analysis = analyze_video_with_gemini(
        video_path,
        title=video['title'],
        description=video.get('description', '')
    )
    
    print(f"\nAnálise concluída!")
    print(f"  - Resumo: {len(analysis.get('summary', ''))} chars")
    print(f"  - Momentos-chave: {len(analysis.get('key_moments', []))}")
    print(f"  - Técnicas: {analysis.get('techniques', [])}")
    print(f"  - Dificuldade: {analysis.get('difficulty', 'N/A')}")
    
    # 3. Salvar análise no banco
    analysis_id = save_analysis_to_db(video['id'], analysis)
    
    # 4. Extrair frames dos momentos importantes
    moments = analysis.get("key_moments", [])
    if moments:
        print(f"\nExtraindo frames de {len(moments)} momentos...")
        
        timestamps = [m.get("timestamp_seconds", 0) for m in moments]
        frames_dir = FRAMES_DIR / str(video['id'])
        
        extracted = extract_frames_batch(video_path, timestamps, frames_dir)
        
        # Atualizar paths no banco
        with DatabaseConnection() as conn:
            with conn.cursor() as cur:
                for ts, frame_path in extracted.items():
                    cur.execute("""
                        UPDATE video_moments
                        SET frame_path = %s
                        WHERE video_id = %s AND timestamp_seconds = %s
                    """, (str(frame_path), video['id'], ts))
                
                cur.execute("""
                    UPDATE videos SET frames_status = 'completed' WHERE id = %s
                """, (video['id'],))
        
        print(f"  ✓ {len(extracted)} frames extraídos")
    
    # 5. Limpar vídeo (manter apenas frames)
    if video_path.exists():
        video_path.unlink()
        print("Vídeo temporário removido")
    
    print(f"\n{'='*60}")
    print(f"✅ Processamento concluído!")
    print(f"   Analysis ID: {analysis_id}")
    print(f"{'='*60}\n")
    
    return analysis


def process_batch(limit: int = 10, source_id: int = None):
    """Processa múltiplos vídeos pendentes."""
    
    with DatabaseConnection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            query = """
                SELECT v.id, v.title, v.external_id
                FROM videos v
                WHERE v.analysis_status = 'pending'
            """
            params = []
            
            if source_id:
                query += " AND v.source_id = %s"
                params.append(source_id)
            
            query += " ORDER BY v.published_at DESC LIMIT %s"
            params.append(limit)
            
            cur.execute(query, params)
            videos = cur.fetchall()
    
    print(f"Encontrados {len(videos)} vídeos para processar\n")
    
    for i, video in enumerate(videos, 1):
        print(f"\n[{i}/{len(videos)}] {video['title'][:50]}...")
        try:
            process_video(video_id=video['id'])
        except Exception as e:
            print(f"❌ Erro: {e}")
            continue
        
        # Pausa entre vídeos para respeitar rate limits
        if i < len(videos):
            print("Aguardando 5s antes do próximo...")
            time.sleep(5)


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="ComfyUI KB - Video Analyzer")
    parser.add_argument("--video-id", type=int, help="ID do vídeo no banco")
    parser.add_argument("--video-url", type=str, help="URL do vídeo YouTube")
    parser.add_argument("--batch", action="store_true", help="Processar batch de vídeos pendentes")
    parser.add_argument("--limit", type=int, default=10, help="Limite de vídeos no batch")
    parser.add_argument("--source-id", type=int, help="Filtrar por source_id")
    parser.add_argument("--skip-download", action="store_true", help="Pular download se vídeo existir")
    
    args = parser.parse_args()
    
    if args.batch:
        process_batch(limit=args.limit, source_id=args.source_id)
    elif args.video_id or args.video_url:
        process_video(
            video_id=args.video_id,
            video_url=args.video_url,
            skip_download=args.skip_download
        )
    else:
        parser.print_help()
