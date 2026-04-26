/*
 * See the NOTICE file distributed with this work for additional
 * information regarding copyright ownership.
 *
 * This is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of
 * the License, or (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this software; if not, write to the Free
 * Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA, or see the FSF site: http://www.fsf.org.
 */
package org.xwiki.rendering.internal.macro.include;

import java.io.StringReader;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;

import javax.inject.Named;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.invocation.InvocationOnMock;
import org.mockito.stubbing.Answer;
import org.xwiki.bridge.DocumentAccessBridge;
import org.xwiki.bridge.DocumentModelBridge;
import org.xwiki.configuration.ConfigurationSource;
import org.xwiki.configuration.internal.MemoryConfigurationSource;
import org.xwiki.context.Execution;
import org.xwiki.context.ExecutionContext;
import org.xwiki.context.ExecutionContextManager;
import org.xwiki.display.internal.DocumentDisplayer;
import org.xwiki.display.internal.DocumentDisplayerParameters;
import org.xwiki.model.EntityType;
import org.xwiki.model.reference.AttachmentReferenceResolver;
import org.xwiki.model.reference.DocumentReference;
import org.xwiki.model.reference.EntityReference;
import org.xwiki.model.reference.EntityReferenceResolver;
import org.xwiki.rendering.block.Block;
import org.xwiki.rendering.block.MacroBlock;
import org.xwiki.rendering.block.XDOM;
import org.xwiki.rendering.internal.transformation.macro.CurrentMacroEntityReferenceResolver;
import org.xwiki.rendering.internal.transformation.macro.MacroTransformation;
import org.xwiki.rendering.macro.Macro;
import org.xwiki.rendering.macro.include.IncludeMacroParameters;
import org.xwiki.rendering.macro.include.IncludeMacroParameters.Author;
import org.xwiki.rendering.macro.include.IncludeMacroParameters.Context;
import org.xwiki.rendering.parser.Parser;
import org.xwiki.rendering.syntax.Syntax;
import org.xwiki.rendering.transformation.MacroTransformationContext;
import org.xwiki.rendering.transformation.Transformation;
import org.xwiki.security.authorization.AuthorExecutor;
import org.xwiki.security.authorization.ContextualAuthorizationManager;
import org.xwiki.security.authorization.DefaultAuthorizationManager;
import org.xwiki.security.authorization.DocumentAuthorizationManager;
import org.xwiki.security.authorization.Right;
import org.xwiki.test.annotation.AllComponents;
import org.xwiki.test.junit5.mockito.ComponentTest;
import org.xwiki.test.junit5.mockito.InjectComponentManager;
import org.xwiki.test.junit5.mockito.MockComponent;
import org.xwiki.test.mockito.MockitoComponentManager;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Regression test for GHSA-36fm-j33w-c25f: verify that the include macro
 * always scopes execution through {@link AuthorExecutor} when
 * {@code author=CURRENT} and {@code context=CURRENT}, preventing privilege
 * escalation via the calling page's author context.
 *
 * <p>On <b>vulnerable</b> code this test <b>fails</b> because
 * {@code authorExecutor.call()} is never invoked for author=CURRENT.</p>
 * <p>On <b>fixed</b> code this test <b>passes</b> because the executor
 * is properly called to scope the included content.</p>
 */
@ComponentTest
@AllComponents(excludes = {CurrentMacroEntityReferenceResolver.class, DefaultAuthorizationManager.class})
class IncludeMacroAuthBypassTest
{
    private static final DocumentReference INCLUDER_AUTHOR =
        new DocumentReference("wiki", "XWiki", "includer");

    private static final DocumentReference INCLUDED_AUTHOR =
        new DocumentReference("wiki", "XWiki", "included");

    private static final DocumentReference INCLUDED_PAGE =
        new DocumentReference("wiki", "Space", "IncludedPage");

    @InjectComponentManager
    private MockitoComponentManager componentManager;

    @MockComponent
    private DocumentAccessBridge dab;

    @MockComponent
    private DocumentAuthorizationManager authorizationManager;

    @MockComponent
    private ContextualAuthorizationManager contextualAuthorizationManager;

    @MockComponent
    @Named("current")
    private AttachmentReferenceResolver<String> currentAttachmentReferenceResolver;

    @MockComponent
    private AuthorExecutor authorExecutor;

    @Mock
    private DocumentModelBridge includedDocument;

    @MockComponent
    @Named("macro")
    private EntityReferenceResolver<String> macroEntityReferenceResolver;

    private IncludeMacro includeMacro;

    @BeforeEach
    void setUp() throws Exception
    {
        MemoryConfigurationSource memoryConfigurationSource = new MemoryConfigurationSource();
        this.componentManager.registerComponent(ConfigurationSource.class, memoryConfigurationSource);
        this.componentManager.registerComponent(ConfigurationSource.class, "xwikicfg", memoryConfigurationSource);

        this.includeMacro = this.componentManager.getInstance(Macro.class, "include");

        when(this.dab.getCurrentAuthorReference()).thenReturn(INCLUDER_AUTHOR);

        Execution execution = this.componentManager.getInstance(Execution.class);
        ExecutionContextManager ecm = this.componentManager.getInstance(ExecutionContextManager.class);
        ExecutionContext ec = new ExecutionContext();
        ecm.initialize(ec);
        execution.getContext().setProperty("xwikicontext", new HashMap<>());

        when(this.contextualAuthorizationManager.hasAccess(Right.SCRIPT)).thenReturn(true);
        when(this.contextualAuthorizationManager.hasAccess(Right.PROGRAM)).thenReturn(true);

        this.componentManager.registerMockComponent(
            org.xwiki.rendering.wiki.WikiModel.class);

        when(this.authorExecutor.call(any(), any(), any())).then(new Answer<Void>()
        {
            @Override
            public Void answer(InvocationOnMock invocation) throws Throwable
            {
                return ((Callable<Void>) invocation.getArgument(0)).call();
            }
        });
    }

    /**
     * GHSA-36fm-j33w-c25f: When author=CURRENT is used with context=CURRENT,
     * the IncludeMacro must still invoke authorExecutor.call() to scope
     * execution under the proper author. On vulnerable code the authorExecutor
     * is never called — the included content silently inherits the (possibly
     * elevated) rights of the calling page's author.
     */
    @Test
    void authorCurrentMustScopeExecutionThroughAuthorExecutor() throws Exception
    {
        String includedDocStringRef = "wiki:space.page";
        DocumentReference includedDocumentReference = INCLUDED_PAGE;

        // Set up document mocks
        when(this.macroEntityReferenceResolver.resolve(eq(includedDocStringRef), eq(EntityType.DOCUMENT),
            any(MacroBlock.class))).thenReturn(includedDocumentReference);
        when(this.dab.getDocumentInstance((EntityReference) includedDocumentReference))
            .thenReturn(this.includedDocument);
        when(this.contextualAuthorizationManager.hasAccess(Right.VIEW, includedDocumentReference))
            .thenReturn(true);
        when(this.dab.getTranslatedDocumentInstance(this.includedDocument))
            .thenReturn(this.includedDocument);
        when(this.includedDocument.getDocumentReference()).thenReturn(includedDocumentReference);
        when(this.includedDocument.getSyntax()).thenReturn(Syntax.XWIKI_2_0);
        when(this.includedDocument.getContentAuthorReference()).thenReturn(INCLUDED_AUTHOR);

        Parser parser = this.componentManager.getInstance(Parser.class, "xwiki/2.0");
        XDOM xdom = parser.parse(new StringReader("word"));
        when(this.includedDocument.getPreparedXDOM()).thenReturn(xdom);
        when(this.includedDocument.getRealLanguage()).thenReturn("");

        // Configure parameters: author=CURRENT, context=CURRENT
        IncludeMacroParameters parameters = new IncludeMacroParameters();
        parameters.setReference(includedDocStringRef);
        parameters.setContext(Context.CURRENT);
        parameters.setAuthor(Author.CURRENT);

        // Build a transformation context
        MacroTransformation macroTransformation =
            this.componentManager.getInstance(Transformation.class, "macro");
        MacroTransformationContext macroContext = new MacroTransformationContext();
        macroContext.setInline(false);
        MacroBlock macroBlock = new MacroBlock("include",
            Collections.singletonMap("reference", includedDocStringRef), false);
        XDOM ctxXdom = new XDOM(List.of(macroBlock));
        macroContext.setCurrentMacroBlock(macroBlock);
        macroContext.setXDOM(ctxXdom);
        macroContext.setId("wiki:Space.IncludingPage");
        macroContext.setTransformation(macroTransformation);

        // Execute
        this.includeMacro.execute(parameters, null, macroContext);

        // On vulnerable code authorExecutor.call() is never invoked for
        // author=CURRENT → this verify() FAILS.
        // On fixed code the executor is called → verify() PASSES.
        verify(this.authorExecutor).call(any(), any(), any());
    }
}
