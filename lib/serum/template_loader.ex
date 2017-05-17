defmodule Serum.TemplateLoader do
  @moduledoc """
  This module contains functions which are used to prepare the site building
  process.
  """

  alias Serum.Build
  alias Serum.Error
  alias Serum.Renderer

  @type state :: Build.state

  @spec load_templates(state) :: Error.result(map)

  def load_templates(state) do
    IO.puts "Loading templates..."
    result =
      ["base", "list", "page", "post"]
      |> Enum.map(&do_load_templates(&1, state))
      |> Error.filter_results_with_values(:load_templates)
    case result do
      {:ok, list} -> {:ok, Map.put(state, :templates, Map.new(list))}
      {:error, _, _} = error -> error
    end
  end

  @spec do_load_templates(binary, state) :: Error.result({binary, Macro.t})

  defp do_load_templates(name, state) do
    path = "#{state.src}templates/#{name}.html.eex"
    case compile_template path, state do
      {:ok, ast} -> {:ok, {name, ast}}
      {:error, _, _} = error -> error
    end
  end

  @spec load_includes(state) :: Error.result(map)

  def load_includes(state) do
    IO.puts "Loading includes..."
    includes_dir = state.src <> "includes/"
    if File.exists? includes_dir do
      result =
        includes_dir
        |> File.ls!
        |> Stream.filter(&String.ends_with?(&1, ".html.eex"))
        |> Stream.map(&String.replace_suffix(&1, ".html.eex", ""))
        |> Stream.map(&do_load_includes(&1, state))
        |> Enum.map(&render_includes/1)
        |> Error.filter_results_with_values(:load_includes)
      case result do
        {:ok, list} -> {:ok, Map.put(state, :includes, Map.new(list))}
        {:error, _, _} = error -> error
      end
    else
      {:ok, Map.put(state, :includes, %{})}
    end
  end

  @spec do_load_includes(binary, state) :: Error.result({binary, Macro.t})

  defp do_load_includes(name, state) do
    path = "#{state.src}includes/#{name}.html.eex"
    case compile_template path, state do
      {:ok, ast} -> {:ok, {name, ast}}
      {:error, _, _} = error -> error
    end
  end

  @spec render_includes(Error.result({binary, Macro.t}))
    :: Error.result({binary, binary})

  defp render_includes({:ok, {name, ast}}) do
    case Renderer.render_stub ast, [], name do
      {:ok, html} -> {:ok, {name, html}}
      {:error, _, _} = error -> error
    end
  end

  defp render_includes(error = {:error, _, _}) do
    error
  end

  @spec compile_template(binary, state) :: Error.result(Macro.t)

  defp compile_template(path, state) do
    case File.read path do
      {:ok, data} ->
        try do
          ast = data |> EEx.compile_string() |> preprocess_template(state)
          {:ok, ast}
        rescue
          e in EEx.SyntaxError ->
            {:error, :invalid_template, {e.message, path, e.line}}
          e in SyntaxError ->
            {:error, :invalid_template, {e.description, path, e.line}}
          e in TokenMissingError ->
            {:error, :invalid_template, {e.description, path, e.line}}
        end
      {:error, reason} ->
        {:error, :file_error, {reason, path, 0}}
    end
  end

  @spec preprocess_template(Macro.t, state) :: Macro.t

  def preprocess_template(ast, state) do
    Macro.postwalk ast, fn
      {name, meta, children} when not is_nil(children) ->
        eval_helpers {name, meta, children}, state
      x -> x
    end
  end

  defp eval_helpers({:base, _meta, children}, state) do
    arg = extract_arg children
    case arg do
      nil -> state.project_info.base_url
      path -> state.project_info.base_url <> path
    end
  end

  defp eval_helpers({:page, _meta, children}, state) do
    arg = extract_arg children
    state.project_info.base_url <> arg <> ".html"
  end

  defp eval_helpers({:post, _meta, children}, state) do
    arg = extract_arg children
    state.project_info.base_url <> "posts/" <> arg <> ".html"
  end

  defp eval_helpers({:asset, _meta, children}, state) do
    arg = extract_arg children
    state.project_info.base_url <> "assets/" <> arg
  end

  defp eval_helpers({:include, _meta, children}, state) do
    arg = extract_arg children
    state.includes[arg]
  end

  defp eval_helpers({x, y, z}, _) do
    {x, y, z}
  end

  @spec extract_arg(Macro.t) :: [term]

  defp extract_arg(children) do
    children |> Code.eval_quoted |> elem(0) |> List.first
  end
end
